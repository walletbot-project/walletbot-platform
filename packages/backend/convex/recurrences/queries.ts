import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const listRecurrences = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        return await ctx.db
            .query('recurrences')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(100)
    },
})
