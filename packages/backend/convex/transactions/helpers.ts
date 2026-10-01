import { v } from 'convex/values'
import type { Doc, Id } from '../_generated/dataModel'
import type { MutationCtx } from '../_generated/server'
import { inflowsByAccount, outflowsByAccount } from '../aggregates'
import { nextSeq, writeTombstone } from '../sync/helpers'
import {
    tagAggregateDetach,
    tagAggregateInsertTransaction,
    tagAggregateReplaceTransaction,
} from '../tags/helpers'

/** The value fields a recurring edit can carry to later occurrences. */
export const occurrencePatch = v.object({
    name: v.optional(v.string()),
    description: v.optional(v.union(v.string(), v.null())),
    amount: v.optional(v.int64()),
    accountId: v.optional(v.string()),
    categoryId: v.optional(v.string()),
})
export type OccurrencePatch = {
    name?: string
    description?: string | null
    amount?: bigint
    accountId?: string
    categoryId?: string
}

export async function aggregateInsert(
    ctx: MutationCtx,
    id: Id<'transactions'>,
): Promise<void> {
    const doc = await ctx.db.get(id)
    if (!doc) return
    await outflowsByAccount.insert(ctx, doc)
    await inflowsByAccount.insert(ctx, doc)
    await tagAggregateInsertTransaction(ctx, doc)
}

export async function aggregateReplace(
    ctx: MutationCtx,
    oldDoc: Doc<'transactions'>,
    id: Id<'transactions'>,
): Promise<void> {
    const newDoc = await ctx.db.get(id)
    if (!newDoc) return
    await outflowsByAccount.replace(ctx, oldDoc, newDoc)
    await inflowsByAccount.replace(ctx, oldDoc, newDoc)
    await tagAggregateReplaceTransaction(ctx, oldDoc, newDoc)
}

/**
 * Soft-deletes one transaction: detaches its tag joins, archives the row and
 * tombstones both, so the change reaches every device.
 *
 * Shared by `v1/transactions/mutations:archive` and by the batched delete of a
 * recurring series' tail — deleting "this and the ones after it" has to leave
 * each occurrence in exactly the state deleting it on its own would.
 */
export async function archiveTransactionRow(
    ctx: MutationCtx,
    userId: string,
    row: Doc<'transactions'>,
): Promise<void> {
    // Detach join rows so tag counts stay accurate.
    const joins = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction', (q) =>
            q.eq('userId', userId).eq('transactionId', row.id),
        )
        .collect()
    for (const j of joins) {
        const jSeq = await nextSeq(ctx, userId)
        await tagAggregateDetach(ctx, j, row)
        await ctx.db.delete(j._id)
        await writeTombstone(ctx, {
            userId,
            tableName: 'transactionTags',
            entityId: j.id,
            seq: jSeq,
        })
    }

    const seq = await nextSeq(ctx, userId)
    await ctx.db.patch(row._id, {
        isArchived: true,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    // Archived docs contribute 0 to sums (see aggregates.ts). Use replace
    // rather than delete so we retain the entry for potential un-archive.
    await aggregateReplace(ctx, row, row._id)
    await writeTombstone(ctx, {
        userId,
        tableName: 'transactions',
        entityId: row.id,
        seq,
    })
}
