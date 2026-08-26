import { AGENT_CONTEXT_CAPS } from '@wallet-bot/shared'
import { v } from 'convex/values'
import { mutation } from '../../_generated/server'
import { nextSeq, writeTombstone } from '../../sync/helpers'
import { requireAuth } from '../../users/helpers'

/** Longest memory the tools accept — memories are one-liners, not documents. */
const MAX_CONTENT_CHARS = 500

function normalizedContent(raw: string): string {
    const content = raw.trim()
    if (!content) throw new Error('Memory content cannot be empty')
    return content.length > MAX_CONTENT_CHARS
        ? content.slice(0, MAX_CONTENT_CHARS)
        : content
}

export const create = mutation({
    args: { id: v.string(), content: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const content = normalizedContent(args.content)

        const existing = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (existing) throw new Error('Memory with that id already exists')

        // The cap is a product rule, not just abuse prevention: past it, the
        // agent is told to consolidate (merge/rewrite via updateMemory,
        // delete leftovers via forgetMemory) instead of appending forever.
        const active = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_archived', (q) =>
                q.eq('userId', userId).eq('isArchived', false),
            )
            .take(AGENT_CONTEXT_CAPS.memories)
        if (active.length >= AGENT_CONTEXT_CAPS.memories) {
            throw new Error(
                'Memory limit reached — consolidate first: merge or rewrite existing memories (updateMemory) and delete obsolete ones (forgetMemory) before adding new ones',
            )
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())
        await ctx.db.insert('agentMemories', {
            userId,
            id: args.id,
            content,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            seq,
        })
        return args.id
    },
})

export const update = mutation({
    args: { id: v.string(), content: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const content = normalizedContent(args.content)
        const row = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row || row.isArchived) throw new Error('Memory not found')

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            content,
            updatedAt: BigInt(Date.now()),
            seq,
        })
    },
})

/** Soft delete + tombstone, like every synced entity. Idempotent. */
export const archive = mutation({
    args: { id: v.string() },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await ctx.db
            .query('agentMemories')
            .withIndex('by_user_id', (q) =>
                q.eq('userId', userId).eq('id', args.id),
            )
            .unique()
        if (!row) return

        const seq = await nextSeq(ctx, userId)
        await ctx.db.patch(row._id, {
            isArchived: true,
            updatedAt: BigInt(Date.now()),
            seq,
        })
        await writeTombstone(ctx, {
            userId,
            tableName: 'agentMemories',
            entityId: args.id,
            seq,
        })
    },
})
