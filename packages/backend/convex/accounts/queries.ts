import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const listAccounts = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        return await ctx.db
            .query('accounts')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(50)
    },
})
