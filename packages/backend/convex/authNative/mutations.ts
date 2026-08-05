import { v } from 'convex/values'
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

// Used on password reset: every native session for the user must die so a
// potentially-compromised device can't keep syncing with the old token.
export const revokeAllSessionTokensForUser = internalMutation({
    args: { userId: v.string() },
    handler: async (ctx, args) => {
        const rows = await ctx.db
            .query('refreshTokens')
            .withIndex('by_userId', (q) => q.eq('userId', args.userId))
            .collect()
        const now = Date.now()
        for (const row of rows) {
            if (row.revokedAt === undefined) {
                await ctx.db.patch(row._id, { revokedAt: now })
            }
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
