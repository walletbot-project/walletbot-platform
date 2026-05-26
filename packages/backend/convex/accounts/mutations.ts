import { v } from 'convex/values'
import { mutation } from '../_generated/server'
import { nextSeq, writeTombstone } from '../sync/helpers'
import { requireAuth } from '../users/helpers'

export const create = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        currency: v.string(),
        description: v.optional(v.string()),
        color: v.optional(v.string()),
        icon: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const existing = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (existing) {
            throw new Error('Account with that id already exists')
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.insert('accounts', {
            userId,
            id: args.id,
            name: args.name,
            currency: args.currency,
            description: args.description,
            color: args.color,
            icon: args.icon,
            archived: false,
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
        color: v.optional(v.string()),
        icon: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) throw new Error('Account not found')

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        const patch: {
            name?: string
            description?: string
            color?: string
            icon?: string
        } = {}
        if (args.name !== undefined) patch.name = args.name
        if (args.description !== undefined) patch.description = args.description
        if (args.color !== undefined) patch.color = args.color
        if (args.icon !== undefined) patch.icon = args.icon

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
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('accounts')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await ctx.db.patch(row._id, {
            archived: true,
            updatedAt: now,
            seq,
        })

        await writeTombstone(ctx, {
            userId,
            tableName: 'accounts',
            entityId: args.id,
            seq,
        })
    },
})
