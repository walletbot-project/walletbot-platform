import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { nextSeq, writeTombstone } from '../sync/helpers'
import { requireUserId } from '../users/helpers'

export const create = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)

        const existing = await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (existing) {
            throw new Error('Category with that id already exists')
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.insert('categories', {
            userId,
            id: args.id,
            name: args.name,
            description: args.description,
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
    },
    handler: async (ctx, args) => {
        const userId = await requireUserId(ctx)
        const row = await ctx.db
            .query('categories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) throw new Error('Category not found')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: { name?: string; description?: string } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.description !== undefined) patch.description = args.description

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
            .query('categories')
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
            tableName: 'categories',
            entityId: args.id,
            seq,
        })
    },
})
