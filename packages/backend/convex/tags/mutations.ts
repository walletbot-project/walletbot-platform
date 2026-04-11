import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { requireAuth } from '../lib/auth'

export const createTag = mutation({
    args: {
        name: v.string(),
        color: v.string(),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)

        // Check for duplicate name
        const existing = await ctx.db
            .query('tags')
            .withIndex('by_userId_and_name', (q) =>
                q
                    .eq('userId', user._id)
                    .eq('name', args.name.trim().toLowerCase()),
            )
            .first()
        if (existing) throw new Error('A tag with this name already exists')

        return await ctx.db.insert('tags', {
            userId: user._id,
            name: args.name.trim().toLowerCase(),
            color: args.color,
        })
    },
})

export const updateTag = mutation({
    args: {
        tagId: v.id('tags'),
        name: v.optional(v.string()),
        color: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const tag = await ctx.db.get(args.tagId)
        if (!tag) throw new Error('Tag not found')
        if (tag.userId !== user._id) throw new Error('Not authorized')

        const patch: Record<string, string> = {}
        if (args.name !== undefined) {
            const newName = args.name.trim().toLowerCase()
            // Check duplicate
            const existing = await ctx.db
                .query('tags')
                .withIndex('by_userId_and_name', (q) =>
                    q.eq('userId', user._id).eq('name', newName),
                )
                .first()
            if (existing && existing._id !== args.tagId) {
                throw new Error('A tag with this name already exists')
            }
            patch.name = newName
        }
        if (args.color !== undefined) patch.color = args.color

        await ctx.db.patch(args.tagId, patch)
    },
})

export const deleteTag = mutation({
    args: {
        tagId: v.id('tags'),
    },
    handler: async (ctx, args) => {
        const user = await requireAuth(ctx)
        const tag = await ctx.db.get(args.tagId)
        if (!tag) throw new Error('Tag not found')
        if (tag.userId !== user._id) throw new Error('Not authorized')

        // Remove tag from all transactions that reference it
        // We query by userId and iterate — tags are stored as an array field
        const transactions = await ctx.db
            .query('transactions')
            .withIndex('by_userId', (q) => q.eq('userId', user._id))
            .take(500)

        for (const tx of transactions) {
            if (tx.tags.includes(args.tagId)) {
                await ctx.db.patch(tx._id, {
                    tags: tx.tags.filter((t) => t !== args.tagId),
                })
            }
        }

        await ctx.db.delete(args.tagId)
    },
})
