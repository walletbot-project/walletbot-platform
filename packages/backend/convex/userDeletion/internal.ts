import { v } from 'convex/values'
import { internal } from '../_generated/api'
import type { Id, TableNames } from '../_generated/dataModel'
import {
    internalMutation,
    internalQuery,
    type MutationCtx,
} from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { createAuth } from '../auth'
import { MAX_REQUESTS_PER_HOUR } from './helpers'

const HOUR_MS = 60 * 60 * 1000

// A deletion whose purge chain died gets retried after this long. Generous
// enough that a healthy purge (which reschedules itself immediately) is never
// mistaken for a stalled one.
const STALLED_AFTER_MS = 15 * 60 * 1000

// How many stalled deletions one cron tick revives.
const STALLED_BATCH = 10

/**
 * Removes the better-auth user (sessions, OAuth/credential accounts, user row).
 *
 * Idempotent by design: `findUserById` returns null once the row is gone, so
 * the recovery branch of `consumeToken` and the stalled-deletion cron can both
 * run this again without failing. Never look the user up by email here — the
 * address is released by this very call, so an email lookup could later match a
 * *different* person who has since signed up with it.
 */
async function deleteAuthUser(ctx: MutationCtx, userId: string): Promise<void> {
    const auth = createAuth(ctx)
    const { internalAdapter } = await auth.$context
    const existing = await internalAdapter.findUserById(userId)
    if (!existing) return
    await internalAdapter.deleteUser(userId)
}

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

// Refusals name their reason so the HTTP handler can tell the user what
// actually happened. It used to return a bare null for both, because every
// outcome collapsed into the same generic success — which meant a throttled
// request, or a request for an account already being deleted, still read as
// "check your inbox" for mail that was never sent.
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
        if (deleted) return { ok: false as const, reason: 'already_deleted' }

        const now = Date.now()
        const recent = await ctx.db
            .query('userDeletionRequests')
            .withIndex('by_email', (q) => q.eq('email', args.email))
            .order('desc')
            .take(MAX_REQUESTS_PER_HOUR)

        const withinHour = recent.filter(
            (row) => row._creationTime > now - HOUR_MS,
        )
        if (withinHour.length >= MAX_REQUESTS_PER_HOUR) {
            return { ok: false as const, reason: 'rate_limited' }
        }

        // Opportunistic cleanup: expired links for this address are dead
        // weight (there is no cron sweeping this table).
        for (const row of recent) {
            if (row.status === 'pending' && row.expiresAt <= now) {
                await ctx.db.delete(row._id)
            }
        }

        const requestId = await ctx.db.insert('userDeletionRequests', {
            ...args,
            status: 'pending',
        })
        return { ok: true as const, requestId }
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
            // recovery path. Re-run the auth delete too: a chain that died
            // before it landed would otherwise leave a signable-in account.
            await deleteAuthUser(ctx, row.userId)
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

        // Drop the better-auth user in the SAME transaction that denylists it.
        // These two facts have to move together: a denylisted user whose auth
        // row still exists can still sign in (Google re-attaches to it) and
        // then fails every authorized call — an account that is impossible to
        // use and whose email is impossible to reuse. Deleting it here also
        // frees the address immediately, so signing up again is a clean new
        // account instead of waiting on the batched purge below.
        await deleteAuthUser(ctx, row.userId)

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
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('agentMemories')
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
            // Terms/Privacy acceptance history. Purged with everything else:
            // the rows carry the user's id, and Privacy §9/§10 promise that
            // account data is hard-deleted, leaving only the post-deletion
            // security record. Keeping them as proof of contract would need a
            // policy amendment first.
            async (n) =>
                deleteRows(
                    await ctx.db
                        .query('legalAcceptances')
                        .withIndex('by_user_document_version', (q) =>
                            q.eq('userId', userId),
                        )
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

// Last step, and a backstop rather than the primary delete: `consumeToken`
// already removed the better-auth user up front, so this normally finds
// nothing. It stays because a deletion started by an older build reached this
// path with the user row still present.
// The deletedUsers denylist row is kept forever — it's what rejects the
// user's still-valid stateless native JWTs.
export const finalizeDeletion = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, { userId }) => {
        await deleteAuthUser(ctx, userId)

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

/**
 * Revives deletions whose purge chain died.
 *
 * `purgeUserData` only reschedules itself on its success path, and Convex does
 * not retry a scheduled mutation that throws — so one failed batch used to
 * strand the request row in 'processing' forever, leaving the user's data on
 * disk and (before the auth delete moved up front) an account that could still
 * be signed into but never used. Any row still 'processing' well past the point
 * a healthy chain would have finished is therefore a dead chain: re-running the
 * purge is safe because every step is idempotent.
 */
export const reviveStalledDeletions = internalMutation({
    args: {},
    handler: async (ctx) => {
        const cutoff = Date.now() - STALLED_AFTER_MS
        // Indexed read, ordered by _creationTime, so the oldest stalled rows
        // come first and a healthy backlog never hides them.
        const stalled = await ctx.db
            .query('userDeletionRequests')
            .withIndex('by_status', (q) => q.eq('status', 'processing'))
            .take(STALLED_BATCH)

        for (const row of stalled) {
            if (row._creationTime > cutoff) continue
            console.warn(
                'userDeletion: reviving stalled deletion',
                JSON.stringify({
                    userId: row.userId,
                    stalledSinceMs: Date.now() - row._creationTime,
                }),
            )
            // The auth row is the part that traps the user, so retry it here
            // and not only in the purge chain.
            await deleteAuthUser(ctx, row.userId)
            await ctx.scheduler.runAfter(
                0,
                internal.userDeletion.internal.purgeUserData,
                { userId: row.userId },
            )
        }
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
