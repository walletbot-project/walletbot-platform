import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id, TableNames } from '../_generated/dataModel'
import { internalMutation, internalQuery } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { createAuth } from '../auth'
import { MAX_REQUESTS_PER_HOUR } from './helpers'

const HOUR_MS = 60 * 60 * 1000

// How many rows a single purge invocation may delete before rescheduling
// itself. Transactions cost extra (two aggregate ops per row), so this stays
// conservative relative to backfill's 256.
const PURGE_BUDGET = 100

export const isUserDeleted = internalQuery({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => {
        const row = await ctx.db
            .query('deletedUsers')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .first()
        return row !== null
    },
})

// Returns null when the email should silently NOT be sent (user already
// deleted, or the address hit the hourly cap) — the HTTP handler answers
// with the same generic success either way, so callers can't enumerate.
// On success returns the row id so the caller can roll the row back if the
// send fails; otherwise a transient Resend error would burn a slot against
// the hourly cap and lock the user out of their own deletion link.
export const createRequest = internalMutation({
    args: {
        userId: v.string(),
        email: v.string(),
        tokenHash: v.string(),
        expiresAt: v.number(),
    },
    handler: async (ctx, args) => {
        const deleted = await ctx.db
            .query('deletedUsers')
            .withIndex('by_userId', (q) => q.eq('userId', args.userId))
            .first()
        if (deleted) return null

        const now = Date.now()
        const recent = await ctx.db
            .query('userDeletionRequests')
            .withIndex('by_email', (q) => q.eq('email', args.email))
            .order('desc')
            .take(MAX_REQUESTS_PER_HOUR)

        const withinHour = recent.filter(
            (row) => row._creationTime > now - HOUR_MS,
        )
        if (withinHour.length >= MAX_REQUESTS_PER_HOUR) return null

        // Opportunistic cleanup: expired links for this address are dead
        // weight (there is no cron sweeping this table).
        for (const row of recent) {
            if (row.status === 'pending' && row.expiresAt <= now) {
                await ctx.db.delete(row._id)
            }
        }

        return await ctx.db.insert('userDeletionRequests', {
            ...args,
            status: 'pending',
        })
    },
})

// Rollback for a request whose email never went out. Only ever called with an
// id createRequest just returned, and a no-op if the row is already gone.
export const deleteRequest = internalMutation({
    args: { requestId: v.id('userDeletionRequests') },
    handler: async (ctx, { requestId }) => {
        const row = await ctx.db.get(requestId)
        if (row) await ctx.db.delete(requestId)
        return null
    },
})

// Consumes an emailed deletion token. On success the user is denylisted
// (blocks the still-valid stateless native JWTs) and the purge is scheduled
// inside the same transaction, so a crash after this commit can't lose the
// deletion.
export const consumeToken = internalMutation({
    args: { tokenHash: v.string() },
    handler: async (ctx, { tokenHash }) => {
        const row = await ctx.db
            .query('userDeletionRequests')
            .withIndex('by_tokenHash', (q) => q.eq('tokenHash', tokenHash))
            .unique()
        if (!row) return { ok: false as const }

        if (row.status === 'processing') {
            // Second click, or a purge chain that died before finalizing —
            // the purge is idempotent, so rescheduling it doubles as the
            // recovery path.
            await ctx.scheduler.runAfter(
                0,
                internal.userDeletion.internal.purgeUserData,
                { userId: row.userId },
            )
            return { ok: true as const, userId: row.userId }
        }

        if (row.expiresAt <= Date.now()) {
            await ctx.db.delete(row._id)
            return { ok: false as const }
        }

        await ctx.db.patch(row._id, { status: 'processing' })

        const alreadyDenylisted = await ctx.db
            .query('deletedUsers')
            .withIndex('by_userId', (q) => q.eq('userId', row.userId))
            .first()
        if (!alreadyDenylisted) {
            await ctx.db.insert('deletedUsers', {
                userId: row.userId,
                deletedAt: Date.now(),
            })
        }

        await ctx.scheduler.runAfter(
            0,
            internal.userDeletion.internal.purgeUserData,
            { userId: row.userId },
        )
        return { ok: true as const, userId: row.userId }
    },
})

// Deletes everything a user owns, PURGE_BUDGET rows at a time, rescheduling
// itself until done (same pattern as transactions/backfill.ts). No tombstones
// and no syncCounters bump on purpose: the user is denylisted before this
// runs, so no client of theirs can pull again — and the point is to leave no
// trace, not to replicate the deletion.
//
// Deliberately NOT purged: `telemetryEvents` and `telemetryMetrics`. Both carry
// an optional `userId` (and an index on it), but they hold no financial rows and
// the ingest contract forbids PII in `properties`/`attributes` — they are
// aggregate product analytics, and dropping a deleted user's rows would silently
// restate historical counts. If that trade is ever revisited, both tables are
// index-ready (`by_userId_and_receivedAt`) and belong here as two more steps.
export const purgeUserData = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => {
        let remaining = PURGE_BUDGET

        const deleteRows = async (
            rows: Array<{ _id: Id<TableNames> }>,
        ): Promise<number> => {
            for (const row of rows) {
                await ctx.db.delete(row._id)
            }
            return rows.length
        }

        // Ordered: sessions first (locks the user out), high-volume tables
        // next, sync bookkeeping last so concurrent mutations from a not-yet
        // -locked-out client still find a counter while data rows remain.
        const steps: Array<(limit: number) => Promise<number>> = [
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('refreshTokens')
                        .withIndex('by_userId', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('voiceSessionEvents')
                        .withIndex(
                            'by_userId_and_sessionId_and_sequence',
                            (q) => q.eq('userId', userId),
                        )
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('voiceSessions')
                        .withIndex('by_userId_and_sessionId', (q) =>
                            q.eq('userId', userId),
                        )
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('transactionTags')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('dashboardWidgets')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('savedFilters')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) => {
                const txs = await ctx.db
                    .query('transactions')
                    .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                    .take(n)
                for (const tx of txs) {
                    // Aggregate entries derive their key from the doc, so
                    // they must go before ctx.db.delete. Per-doc deletes
                    // only — inflows' shared '__none__' namespace holds
                    // every user's non-transfers, so clear() would corrupt
                    // other users' balances.
                    await outflowsByAccount.deleteIfExists(ctx, tx)
                    await inflowsByAccount.deleteIfExists(ctx, tx)
                    await ctx.db.delete(tx._id)
                }
                return txs.length
            },
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('tags')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('categories')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('accounts')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('userSettings')
                        .withIndex('by_user', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('featureFlagOverrides')
                        .withIndex('by_user', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            // Holds the user's email as well as their id, so leaving it behind
            // would keep an address alive after the account is "deleted".
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('admins')
                        .withIndex('by_user_id', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('tombstones')
                        .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                        .take(n),
                ),
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('syncCounters')
                        .withIndex('by_user', (q) => q.eq('userId', userId))
                        .take(n),
                ),
        ]

        for (const step of steps) {
            if (remaining === 0) break
            remaining -= await step(remaining)
        }

        if (remaining === 0) {
            // Budget exhausted — rows may remain; run again. (At worst this
            // schedules one extra no-op pass.)
            await ctx.scheduler.runAfter(
                0,
                internal.userDeletion.internal.purgeUserData,
                { userId },
            )
            return null
        }

        await ctx.scheduler.runAfter(
            0,
            internal.userDeletion.internal.finalizeDeletion,
            { userId },
        )
        return null
    },
})

// Last step: remove the better-auth user (sessions, credential + OAuth
// accounts, user row), then hand off to the request-row sweep.
// The deletedUsers denylist row is kept forever — it's what rejects the
// user's still-valid stateless native JWTs.
export const finalizeDeletion = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => {
        const auth = createAuth(ctx)
        const authCtx = await auth.$context
        await authCtx.internalAdapter.deleteUser(userId)

        // Separate mutation so the reschedule loop below can't re-run
        // deleteUser on an already-deleted user.
        await ctx.scheduler.runAfter(
            0,
            internal.userDeletion.internal.purgeDeletionRequests,
            { userId },
        )
        return null
    },
})

// Drains our own request rows, which hold the user's email. The hourly cap in
// createRequest only bounds *recent* requests, so a long-lived account can
// have accumulated far more than one batch — a single bounded take() would
// strand the rest, leaving the email behind after the account is "deleted".
// Reschedules until a short batch proves the table is clear, mirroring
// purgeUserData.
export const purgeDeletionRequests = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => {
        const rows = await ctx.db
            .query('userDeletionRequests')
            .withIndex('by_userId', (q) => q.eq('userId', userId))
            .take(PURGE_BUDGET)
        for (const row of rows) {
            await ctx.db.delete(row._id)
        }

        if (rows.length === PURGE_BUDGET) {
            await ctx.scheduler.runAfter(
                0,
                internal.userDeletion.internal.purgeDeletionRequests,
                { userId },
            )
        }
        return null
    },
})
