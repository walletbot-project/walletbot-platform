import { pastCutoffBigInt } from '@wallet-bot/shared'
import { internal } from '../_generated/api'
import type { Doc } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import { nextSeq } from '../sync/helpers'

export async function resolveOccurrenceCutoff(
    ctx: QueryCtx,
    asOfMs?: bigint,
): Promise<bigint> {
    if (asOfMs !== undefined) return asOfMs
    const clock = await ctx.db
        .query('occurrenceClock')
        .withIndex('by_key', (q) => q.eq('key', 'singleton'))
        .unique()
    return clock?.cutoff ?? pastCutoffBigInt()
}

// A hidden transaction's joins were absent on legacy devices too. They need
// fresh sync seqs when the transaction becomes visible, including a date edit.
export async function republishTransactionTags(
    ctx: MutationCtx,
    row: Pick<Doc<'transactions'>, 'id' | 'userId'>,
    cursor: string | null = null,
): Promise<void> {
    const page = await ctx.db
        .query('transactionTags')
        .withIndex('by_user_transaction', (q) =>
            q.eq('userId', row.userId).eq('transactionId', row.id),
        )
        .paginate({ numItems: 50, cursor })
    for (const join of page.page) {
        await ctx.db.patch(join._id, { seq: await nextSeq(ctx, row.userId) })
    }
    if (!page.isDone)
        await ctx.scheduler.runAfter(
            0,
            internal.occurrences.internal.republishTags,
            { userId: row.userId, id: row.id, cursor: page.continueCursor },
        )
}

/** Every transaction write maintains the indexed queue, including reschedules. */
export async function trackFutureOccurrence(
    ctx: MutationCtx,
    row: Doc<'transactions'>,
): Promise<void> {
    const pending =
        !row.isArchived && row.date >= pastCutoffBigInt() ? row.date : undefined
    if (pending !== row.legacyPendingDate) {
        await ctx.db.patch(row._id, { legacyPendingDate: pending })
    }
}
