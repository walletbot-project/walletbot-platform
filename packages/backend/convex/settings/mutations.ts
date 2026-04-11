import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../lib/auth'
import { currencyValidator } from '../lib/validators'

export const updateUserSettings = mutation({
    args: {
        defaultCurrency: v.optional(currencyValidator),
        locale: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        const existing = await ctx.db
            .query('userSettings')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .first()

        if (existing) {
            const patch: Record<string, string> = {}
            if (args.defaultCurrency !== undefined)
                patch.defaultCurrency = args.defaultCurrency
            if (args.locale !== undefined) patch.locale = args.locale
            await ctx.db.patch(existing._id, patch)
        } else {
            await ctx.db.insert('userSettings', {
                userId: user._id,
                defaultCurrency: args.defaultCurrency ?? 'USD',
                locale: args.locale ?? 'en-US',
            })
        }
    },
})
