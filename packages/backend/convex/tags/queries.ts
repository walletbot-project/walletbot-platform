import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const listTags = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        return await ctx.db
            .query('tags')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(100)
    },
})
