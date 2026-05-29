import { v } from 'convex/values'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import { mutation } from '../_generated/server'
import { nextSeq, writeTombstone } from '../sync/helpers'
import { requireAuth } from '../users/helpers'

async function getTagById(
    ctx: MutationCtx,
    userId: string,
    tagId: string,
): Promise<Doc<'tags'> | null> {
    return await ctx.db
        .query('tags')
        .withIndex('by_user_id', (q) => q.eq('userId', userId).eq('id', tagId))
        .unique()
}

// Walks the parent chain upward starting at `startParentId`, collecting tag
// ids in order from nearest to farthest ancestor. Returns null if it would
// reach `forbiddenId` (i.e. a cycle would form).
async function collectAncestorIds(
    ctx: MutationCtx,
    userId: string,
    startParentId: string,
    forbiddenId: string,
): Promise<string[] | null> {
    const ancestors: string[] = []
    const seen = new Set<string>()
    let cursor: string | undefined = startParentId
    while (cursor) {
        if (cursor === forbiddenId) return null
        if (seen.has(cursor)) break
        seen.add(cursor)
        ancestors.push(cursor)
        const parent: Doc<'tags'> | null = await getTagById(ctx, userId, cursor)
        if (!parent || parent.isArchived) break
        cursor = parent.parentId
    }
    return ancestors
}

async function collectDescendantIds(
    ctx: MutationCtx,
    userId: string,
    rootId: string,
): Promise<string[]> {
    const out: string[] = []
    const queue: string[] = [rootId]
    while (queue.length > 0) {
        const id = queue.shift() as string
        const children = await ctx.db
            .query('tags')
            .withIndex('by_user_parent', (q) =>
                q.eq('userId', userId).eq('parentId', id),
            )
            .collect()
        for (const child of children) {
            if (child.isArchived) continue
            out.push(child.id)
            queue.push(child.id)
        }
    }
    return out
}

async function ensureTransactionTag(
    ctx: MutationCtx,
    userId: string,
    transactionId: string,
    tagId: string,
): Promise<void> {
    const existing = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction_tag', (q) =>
            q
                .eq('userId', userId)
                .eq('transactionId', transactionId)
                .eq('tagId', tagId),
        )
        .unique()
    if (existing) return

    const seq = await nextSeq(ctx, userId)
    const now = BigInt(Date.now())
    await ctx.db.insert('transactionTags', {
        userId,
        id: crypto.randomUUID(),
        transactionId,
        tagId,
        createdAt: now,
        updatedAt: now,
        seq,
    })
}

// Writes a tag row, omitting `parentId` entirely when newParentId is null so
// the field is fully removed from the document. Using db.replace avoids any
// ambiguity with `db.patch(..., { parentId: undefined })`.
async function replaceTagWith(
    ctx: MutationCtx,
    row: Doc<'tags'>,
    next: {
        name?: string
        description?: string | undefined
        color?: string | undefined
        parentId?: string | null
        isArchived?: boolean
        updatedAt: bigint
        seq: bigint
    },
): Promise<void> {
    const baseParent =
        next.parentId === null
            ? undefined
            : next.parentId === undefined
              ? row.parentId
              : next.parentId
    const description =
        next.description === undefined ? row.description : next.description
    const color = next.color === undefined ? row.color : next.color

    const doc: {
        userId: string
        id: string
        name: string
        isArchived: boolean
        createdAt: bigint
        updatedAt: bigint
        seq: bigint
        description?: string
        parentId?: string
        color?: string
    } = {
        userId: row.userId,
        id: row.id,
        name: next.name ?? row.name,
        isArchived: next.isArchived ?? row.isArchived,
        createdAt: row.createdAt,
        updatedAt: next.updatedAt,
        seq: next.seq,
    }
    if (description !== undefined) doc.description = description
    if (baseParent !== undefined) doc.parentId = baseParent
    if (color !== undefined) doc.color = color

    await ctx.db.replace(row._id, doc)
}

export const create = mutation({
    args: {
        id: v.string(),
        name: v.string(),
        description: v.optional(v.string()),
        parentId: v.optional(v.string()),
        color: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)

        const existing = await getTagById(ctx, userId, args.id)
        if (existing) throw new Error('Tag with that id already exists')

        if (args.parentId) {
            if (args.parentId === args.id) {
                throw new Error('A tag cannot be its own parent')
            }
            const parent = await getTagById(ctx, userId, args.parentId)
            if (!parent || parent.isArchived) {
                throw new Error('Parent tag not found')
            }
        }

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
        // null = clear parent, string = set parent, undefined = unchanged
        parentId: v.optional(v.union(v.string(), v.null())),
        color: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTagById(ctx, userId, args.id)
        if (!row) throw new Error('Tag not found')

        let newAncestorChain: string[] = []
        if (typeof args.parentId === 'string') {
            if (args.parentId === args.id) {
                throw new Error('A tag cannot be its own parent')
            }
            const parent = await getTagById(ctx, userId, args.parentId)
            if (!parent || parent.isArchived) {
                throw new Error('Parent tag not found')
            }
            const chain = await collectAncestorIds(
                ctx,
                userId,
                args.parentId,
                args.id,
            )
            if (chain === null) {
                throw new Error('A tag cannot be made a descendant of itself')
            }
            newAncestorChain = chain
        }

        const seq = await nextSeq(ctx, userId)
        const now = BigInt(Date.now())

        await replaceTagWith(ctx, row, {
            name: args.name,
            description: args.description,
            color: args.color,
            parentId: args.parentId,
            updatedAt: now,
            seq,
        })

        // When a parent is set or changed, every transaction tagged with this
        // tag (or any of its descendants) must also carry every ancestor in
        // the new chain.
        const parentChanged =
            args.parentId !== undefined &&
            (args.parentId === null
                ? row.parentId !== undefined
                : args.parentId !== row.parentId)
        if (parentChanged && newAncestorChain.length > 0) {
            const descendantIds = await collectDescendantIds(
                ctx,
                userId,
                args.id,
            )
            const affectedTagIds = [args.id, ...descendantIds]
            const transactionIds = new Set<string>()
            for (const tagId of affectedTagIds) {
                const joins = await ctx.db
                    .query('transactionTags')
                    .withIndex('by_user_tag', (q) =>
                        q.eq('userId', userId).eq('tagId', tagId),
                    )
                    .collect()
                for (const j of joins) transactionIds.add(j.transactionId)
            }
            for (const transactionId of transactionIds) {
                for (const ancestorId of newAncestorChain) {
                    await ensureTransactionTag(
                        ctx,
                        userId,
                        transactionId,
                        ancestorId,
                    )
                }
            }
        }
    },
})

export const archive = mutation({
    args: {
        id: v.string(),
        // When true, descendant tags are archived too. When false, direct
        // children are re-parented to the deleted tag's parent (becoming
        // top-level when the deleted tag had no parent); their own descendants
        // stay attached to them.
        cascade: v.optional(v.boolean()),
    },
    handler: async (ctx, args) => {
        const userId = await requireAuth(ctx)
        const row = await getTagById(ctx, userId, args.id)
        if (!row) return

        if (args.cascade) {
            const descendantIds = await collectDescendantIds(
                ctx,
                userId,
                args.id,
            )
            for (const descendantId of descendantIds) {
                const descendant = await getTagById(ctx, userId, descendantId)
                if (!descendant || descendant.isArchived) continue
                const dSeq = await nextSeq(ctx, userId)
                const dNow = BigInt(Date.now())
                await ctx.db.patch(descendant._id, {
                    isArchived: true,
                    updatedAt: dNow,
                    seq: dSeq,
                })
                await writeTombstone(ctx, {
                    userId,
                    tableName: 'tags',
                    entityId: descendant.id,
                    seq: dSeq,
                })
            }
        } else {
            const directChildren = await ctx.db
                .query('tags')
                .withIndex('by_user_parent', (q) =>
                    q.eq('userId', userId).eq('parentId', args.id),
                )
                .collect()
            for (const child of directChildren) {
                if (child.isArchived) continue
                const cSeq = await nextSeq(ctx, userId)
                const cNow = BigInt(Date.now())
                await replaceTagWith(ctx, child, {
                    parentId: row.parentId ?? null,
                    updatedAt: cNow,
                    seq: cSeq,
                })
            }
        }

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
