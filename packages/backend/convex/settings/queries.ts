import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const getUserSettings = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        const settings = await ctx.db
            .query('userSettings')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .first()

        // Return defaults if no settings exist yet
        return (
            settings ?? {
                defaultCurrency: 'USD',
                locale: 'en-US',
            }
        )
    },
})
