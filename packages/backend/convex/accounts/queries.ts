import { v } from 'convex/values'
import { query } from '../_generated/server'
import { requireAuth } from '../users/helpers'

export const listActive = query({
    args: {},
    handler: async (ctx) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('accounts')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('archived', false),
            )
            .collect()
    },
})

export const list = query({
    args: { includeArchived: v.optional(v.boolean()) },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        if (args.includeArchived) {
            return await ctx.db
                .query('accounts')
                .withIndex('by_user_seq', (q) => q.eq('userId', userId))
                .collect()
        }
        return await ctx.db
            .query('accounts')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('archived', false),
            )
            .collect()
    },
})

export const get = query({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        return await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
    },
})
