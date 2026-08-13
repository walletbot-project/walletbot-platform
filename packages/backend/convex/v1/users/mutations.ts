import { isValidCurrencyCode } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { requireAuth } from '../../users/helpers'

export const updateDefaultCurrency = mutation({
    args: { currency: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (!isValidCurrencyCode(args.currency)) {
            throw new Error('Invalid currency code')
        }

        const existing = await ctx.db
            .query('userSettings')
            .withIndex('by_user', (q) => q.eq('userId', userId))
            .unique()

        const now = BigInt(Date.now())
        if (existing) {
            await ctx.db.patch(existing._id, {
                defaultCurrency: args.currency,
                updatedAt: now,
            })
        } else {
            await ctx.db.insert('userSettings', {
                userId,
                defaultCurrency: args.currency,
                updatedAt: now,
            })
        }
    },
})
