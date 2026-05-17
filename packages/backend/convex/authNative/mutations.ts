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
