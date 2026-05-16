import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { nextSeq, writeTombstone } from '../sync/helpers'
import { requireUserId } from '../users/helpers'

export const create = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
        parentId: v.optional(v.string()),
        color: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)

        const existing = await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (existing) throw new Error('Tag with that id already exists')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.insert('tags', {
            userId,
            id: args.id,
            name: args.name,
            description: args.description,
            parentId: args.parentId,
            color: args.color,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })

        return args.id
    },
})

export const update = mutation({
    args: {
        id: v.string(),
        name: v.optional(v.string()),
        description: v.optional(v.string()),
        parentId: v.optional(v.string()),
        color: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)
        const row = await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) throw new Error('Tag not found')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: {
            name?: string
            description?: string
            parentId?: string
            color?: string
        } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.description !== undefined) patch.description = args.description
        if (args.parentId !== undefined) patch.parentId = args.parentId
        if (args.color !== undefined) patch.color = args.color

        await ctx.db.patch(row._id, {
            ...patch,
            updatedAt: now,
            seq,
        })
    },
})

export const archive = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)
        const row = await ctx.db
            .query('tags')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: now,
            seq,
        })

        await writeTombstone(ctx, {
            userId,
            tableName: 'tags',
            entityId: args.id,
            seq,
        })
    },
})
