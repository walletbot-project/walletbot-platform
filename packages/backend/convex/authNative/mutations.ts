import { v } from 'convex/values'
import { internal } from '../_generated/api'
import { internalMutation } from '../_generated/server'

export const insertSessionToken = internalMutation({
    args: {
        userId: v.string(),
        tokenHash: v.string(),
        createdAt: v.number(),
        userAgent: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        await ctx.db.insert('refreshTokens', args)
        return null
    },
})

export const validateSessionToken = internalMutation({
    args: { tokenHash: v.string() },
    handler: async (ctx, args) => {
        const row = await ctx.db
            .query('refreshTokens')
            .withIndex('by_tokenHash', (q) => q.eq('tokenHash', args.tokenHash))
            .unique()

        if (!row) {
            return { ok: false as const, reason: 'not_found' as const }
        }
        if (row.revokedAt !== undefined) {
            return { ok: false as const, reason: 'revoked' as const }
        }
        // Legacy rows from the old rotating design may still carry expiresAt;
        // honor it so they don't outlive their original lifetime.
        if (row.expiresAt !== undefined && row.expiresAt <= Date.now()) {
            return { ok: false as const, reason: 'expired' as const }
        }
        return { ok: true as const, userId: row.userId }
    },
})

// Rows per transaction. `refreshTokens` rows are never deleted and every
// sign-in inserts one, so a long-lived account can accumulate more than a
// single Convex transaction may write (16k writes / 32k scanned docs).
const REVOKE_BATCH_SIZE = 256

// Used on password reset: every native session for the user must die so a
// potentially-compromised device can't keep syncing with the old token.
//
// Revokes in bounded batches, rescheduling itself while a full batch comes
// back. The index range only covers rows with `revokedAt: undefined`, so every
// patch shrinks the remaining work and the loop terminates. The first batch
// runs inline, so the caller's own sessions die before the request returns.
export const revokeAllSessionTokensForUser = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, args) => {
        const rows = await ctx.db
            .query('refreshTokens')
            .withIndex('by_userId_revokedAt', (q) =>
                q.eq('userId', args.userId).eq('revokedAt', undefined),
            )
            .take(REVOKE_BATCH_SIZE)

        const now = Date.now()
        for (const row of rows) {
            await ctx.db.patch(row._id, { revokedAt: now })
        }

        if (rows.length === REVOKE_BATCH_SIZE) {
            await ctx.scheduler.runAfter(
                0,
                internal.authNative.mutations.revokeAllSessionTokensForUser,
                { userId: args.userId },
            )
        }
        return null
    },
})

export const revokeSessionTokenByHash = internalMutation({
    args: { tokenHash: v.string() },
    handler: async (ctx, args) => {
        const row = await ctx.db
            .query('refreshTokens')
            .withIndex('by_tokenHash', (q) => q.eq('tokenHash', args.tokenHash))
            .unique()
        if (!row || row.revokedAt !== undefined) return null
        await ctx.db.patch(row._id, { revokedAt: Date.now() })
        return null
    },
})
