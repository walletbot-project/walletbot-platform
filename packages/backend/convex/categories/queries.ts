import { query } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const listCategories = query({
    args: {},
    handler: async (ctx) => {
        const user = await requireAuth(ctx)

        // System categories
        const system = await ctx.db
            .query('categories')
            .withIndex('by_isSystem', (q) => q.eq('isSystem', true))
            .take(50)

        // User's custom categories
        const custom = await ctx.db
            .query('categories')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(100)

        const all = [...system, ...custom]

        // Build tree: top-level + their children
        const topLevel = all.filter((c) => !c.parentId)
        const children = all.filter((c) => c.parentId)

        return topLevel
            .sort((a, b) => a.sortOrder - b.sortOrder)
            .map((parent) => ({
                ...parent,
                children: children
                    .filter((c) => c.parentId === parent._id)
                    .sort((a, b) => a.sortOrder - b.sortOrder),
            }))
    },
})
