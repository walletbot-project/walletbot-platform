import { v } from 'convex/values'
import { internalMutation } from '../_generated/server'

export const insertRefreshToken = internalMutation({
    args: {
        userId: v.string(),
        tokenHash: v.string(),
        family: v.string(),
        expiresAt: v.number(),
        createdAt: v.number(),
        userAgent: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        await ctx.db.insert('refreshTokens', args)
        return null
    },
})

export const rotateRefreshToken = internalMutation({
    args: {
        presentedHash: v.string(),
        newHash: v.string(),
        newExpiresAt: v.number(),
        newCreatedAt: v.number(),
    },
    handler: async (ctx, args) => {
        const presented = await ctx.db
            .query('refreshTokens')
            .withIndex('by_tokenHash', (q) =>
                q.eq('tokenHash', args.presentedHash),
            )
            .unique()

        if (!presented) {
            return { ok: false as const, reason: 'not_found' as const }
        }

        if (presented.revokedAt !== undefined) {
            // Refresh-token reuse: assume the family is compromised and revoke
            // every still-live row sharing it. Caller must force re-auth.
            const familyRows = await ctx.db
                .query('refreshTokens')
                .withIndex('by_family', (q) => q.eq('family', presented.family))
                .take(256)
            const now = Date.now()
            for (const row of familyRows) {
                if (row.revokedAt === undefined) {
                    await ctx.db.patch(row._id, { revokedAt: now })
                }
            }
            return { ok: false as const, reason: 'revoked' as const }
        }

        if (presented.expiresAt <= Date.now()) {
            return { ok: false as const, reason: 'expired' as const }
        }

        const newId = await ctx.db.insert('refreshTokens', {
            userId: presented.userId,
            tokenHash: args.newHash,
            family: presented.family,
            expiresAt: args.newExpiresAt,
            createdAt: args.newCreatedAt,
            userAgent: presented.userAgent,
        })
        await ctx.db.patch(presented._id, {
            revokedAt: Date.now(),
            replacedBy: newId,
        })

        return { ok: true as const, userId: presented.userId }
    },
})

export const revokeRefreshTokenByHash = internalMutation({
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
