import type { Doc } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import { tagNamespace, transactionsByTag } from '../aggregates'

/** The fields of a join row the aggregate entry is derived from. */
export type TagJoin = Pick<
    Doc<'transactionTags'>,
    'userId' | 'id' | 'transactionId' | 'tagId'
>

function entry(join: TagJoin, date: bigint) {
    return {
        namespace: tagNamespace(join.userId, join.tagId),
        key: date,
        id: join.id,
    }
}

async function transactionOf(
    ctx: QueryCtx,
    join: TagJoin,
): Promise<Doc<'transactions'> | null> {
    return await ctx.db
        .query('transactions')
        .withIndex('by_user_id', (q) =>
            q.eq('userId', join.userId).eq('id', join.transactionId),
        )
        .unique()
}

async function joinsOf(
    ctx: QueryCtx,
    transaction: Doc<'transactions'>,
): Promise<Doc<'transactionTags'>[]> {
    return await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction', (q) =>
            q
                .eq('userId', transaction.userId)
                .eq('transactionId', transaction.id),
        )
        .collect()
}

/**
 * Records a join in the tag aggregate. Call after inserting the join; pass the
 * transaction when the caller already holds it to save the read.
 */
export async function tagAggregateAttach(
    ctx: MutationCtx,
    join: TagJoin,
    transaction?: Doc<'transactions'> | null,
): Promise<void> {
    const txn =
        transaction === undefined ? await transactionOf(ctx, join) : transaction
    if (!txn || txn.isArchived) return
    await transactionsByTag.insertIfDoesNotExist(ctx, entry(join, txn.date))
}

/**
 * Drops a join's entry. Call before deleting the join, while its transaction
 * still exists, since the entry is keyed by the transaction's date.
 */
export async function tagAggregateDetach(
    ctx: MutationCtx,
    join: TagJoin,
    transaction?: Doc<'transactions'> | null,
): Promise<void> {
    const txn =
        transaction === undefined ? await transactionOf(ctx, join) : transaction
    if (!txn) return
    await transactionsByTag.deleteIfExists(ctx, entry(join, txn.date))
}

/** Entries for a transaction that has just been inserted. */
export async function tagAggregateInsertTransaction(
    ctx: MutationCtx,
    transaction: Doc<'transactions'>,
): Promise<void> {
    if (transaction.isArchived) return
    for (const join of await joinsOf(ctx, transaction)) {
        await transactionsByTag.insertIfDoesNotExist(
            ctx,
            entry(join, transaction.date),
        )
    }
}

/**
 * Re-keys or drops a transaction's entries when its date or archive state
 * changes. Any other edit leaves the aggregate untouched.
 */
export async function tagAggregateReplaceTransaction(
    ctx: MutationCtx,
    oldDoc: Doc<'transactions'>,
    newDoc: Doc<'transactions'>,
): Promise<void> {
    if (
        oldDoc.date === newDoc.date &&
        oldDoc.isArchived === newDoc.isArchived
    ) {
        return
    }
    for (const join of await joinsOf(ctx, newDoc)) {
        if (newDoc.isArchived) {
            if (!oldDoc.isArchived) {
                await transactionsByTag.deleteIfExists(
                    ctx,
                    entry(join, oldDoc.date),
                )
            }
            continue
        }
        if (oldDoc.isArchived) {
            await transactionsByTag.insertIfDoesNotExist(
                ctx,
                entry(join, newDoc.date),
            )
            continue
        }
        await transactionsByTag.replaceOrInsert(
            ctx,
            entry(join, oldDoc.date),
            { namespace: tagNamespace(join.userId, join.tagId), key: newDoc.date },
        )
    }
}

/** Entries for a transaction about to be hard-deleted. */
export async function tagAggregateDeleteTransaction(
    ctx: MutationCtx,
    transaction: Doc<'transactions'>,
): Promise<void> {
    for (const join of await joinsOf(ctx, transaction)) {
        await transactionsByTag.deleteIfExists(
            ctx,
            entry(join, transaction.date),
        )
    }
}

/** How many live transactions carry `tagId` and are dated before `asOfMs`. */
export async function countTaggedBefore(
    ctx: QueryCtx,
    userId: string,
    tagId: string,
    asOfMs: bigint,
): Promise<number> {
    return await transactionsByTag.count(ctx, {
        namespace: tagNamespace(userId, tagId),
        bounds: { upper: { key: asOfMs, inclusive: false } },
    })
}
