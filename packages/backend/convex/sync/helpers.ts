import type { MutationCtx } from '../_generated/server'

export async function nextSeq(
    ctx: MutationCtx,
    userId: string,
): Promise<bigint> {
    const row = await ctx.db
        .query('syncCounters')
        .withIndex('by_user', (q) => q.eq('userId', userId))
        .unique()

    const next = (row?.value ?? 0n) + 1n
    if (row) {
        await ctx.db.patch(row._id, { value: next })
    } else {
        await ctx.db.insert('syncCounters', { userId, value: next })
    }
    return next
}

export async function writeTombstone(
    ctx: MutationCtx,
    args: {
        userId: string
        tableName:
            | 'accounts'
            | 'categories'
            | 'transactions'
            | 'tags'
            | 'transactionTags'
            | 'savedFilters'
            | 'dashboardWidgets'
        entityId: string
        seq: bigint
        // Only meaningful for `tableName: 'accounts'` — see schema/sync.ts.
        mergedIntoId?: string
    },
): Promise<void> {
    const existing = await ctx.db
        .query('tombstones')
        .withIndex('by_user_table_entity', (q) =>
            q
                .eq('userId', args.userId)
                .eq('tableName', args.tableName)
                .eq('entityId', args.entityId),
        )
        .unique()

    const now = BigInt(Date.now())
    if (existing) {
        await ctx.db.patch(existing._id, {
            seq: args.seq,
            deletedAt: now,
            ...(args.mergedIntoId !== undefined && {
                mergedIntoId: args.mergedIntoId,
            }),
        })
    } else {
        await ctx.db.insert('tombstones', {
            userId: args.userId,
            tableName: args.tableName,
            entityId: args.entityId,
            seq: args.seq,
            deletedAt: now,
            mergedIntoId: args.mergedIntoId,
        })
    }
}
