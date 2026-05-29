import { v } from 'convex/values'
import { query } from '../_generated/server'
import { requireAuth } from '../users/helpers'

export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('tags')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()
    },
})

export const listActiveWithCounts = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        const tags = await ctx.db
            .query('tags')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .collect()

        const withCounts = await Promise.all(
            tags.map(async (tag) => {
                const joins = await ctx.db
                    .query('transactionTags')
                    .withIndex('by_user_tag', (q) =>
                        q.eq('userId', userId).eq('tagId', tag.id),
                    )
                    .collect()
                return {
                    ...tag,
                    transactionCount: joins.length,
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
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})
