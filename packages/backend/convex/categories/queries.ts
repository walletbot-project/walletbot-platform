import { v } from 'convex/values'
import { query } from '../_generated/server'
import { requireUserId } from '../users/helpers'

export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireUserId(ctx)
        return await ctx.db
            .query('categories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
    },
})

export const listActiveWithCounts = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireUserId(ctx)
        const categories = await ctx.db
            .query('categories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()

        const withCounts = await Promise.all(
            categories.map(async (category) => {
                const txns = await ctx.db
                    .query('transactions')
                    .withIndex('by_user_category_date', (q) =>
                        q.eq('userId', userId).eq('categoryId', category.id),
                    )
                    .collect()
                return {
                    ...category,
                    transactionCount: txns.filter((t) => !t.isArchived).length,
                }
            }),
        )

        return withCounts.sort((a, b) =>
            a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }),
        )
    },
})

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)
        return await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})
