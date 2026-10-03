import {
    adjustmentAmount,
    compareLedgerOrder,
    isBeforeInLedger,
    type LedgerEntry,
    ledgerDelta,
} from '@wallet-bot/shared'
import { v } from 'convex/values'
import type { Doc, Id } from '../_generated/dataModel'
import type { MutationCtx, QueryCtx } from '../_generated/server'
import {
    accountNamespace,
    inflowsByAccount,
    outflowsByAccount,
} from '../aggregates'
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

/**
 * Records a freshly inserted transaction in the aggregates and re-derives the
 * balance adjustment it lands before. Every transaction insert goes through
 * here, which is what keeps every adjustment's declaration true.
 */
export async function aggregateInsert(
    ctx: MutationCtx,
    id: Id<'transactions'>,
): Promise<void> {
    const doc = await ctx.db.get(id)
    if (!doc) return
    await outflowsByAccount.insert(ctx, doc)
    await inflowsByAccount.insert(ctx, doc)
    await tagAggregateInsertTransaction(ctx, doc)
    await reconcileAfterLedgerChange(ctx, null, doc)
}

/**
 * Moves a patched transaction's aggregate entries and re-derives the balance
 * adjustments its old and new positions sit before.
 */
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
    await reconcileAfterLedgerChange(ctx, oldDoc, newDoc)
}

// ───── Balance adjustments ─────
//
// An adjustment declares "this account holds `balanceAfter` at this moment";
// its `amount` is only the difference from what the ledger computed, so it is
// re-derived whenever a movement before it changes. The rule itself lives in
// `@wallet-bot/shared` (balance-adjustment.ts). Here it is applied
// incrementally: a change at one position reaches only the first live
// adjustment after it on each account it touches — that adjustment pins the
// balance, so every later one is unaffected.

/** The accounts whose balance an entry moves. */
function touchedAccounts(entry: LedgerEntry): string[] {
    if (entry.type === 'transfer' && entry.toAccountId) {
        return [entry.accountId, entry.toAccountId]
    }
    return [entry.accountId]
}

/** Whether an edit changed anything a balance is computed from. */
function ledgerChanged(a: LedgerEntry, b: LedgerEntry): boolean {
    return (
        a.isArchived !== b.isArchived ||
        a.type !== b.type ||
        a.accountId !== b.accountId ||
        a.toAccountId !== b.toAccountId ||
        a.amount !== b.amount ||
        a.toAmount !== b.toAmount ||
        a.balanceAfter !== b.balanceAfter ||
        a.date !== b.date ||
        a.createdAt !== b.createdAt
    )
}

/**
 * `accountId`'s balance from every live movement before `entry` in ledger
 * order. Everything on an earlier date is an O(log n) aggregate sum; only the
 * rows sharing `entry`'s exact date are read, to break the tie — a set bounded
 * to one millisecond on one account.
 *
 * `entry` need not be stored yet: an adjustment about to be inserted is
 * measured the same way, so it is created with its final amount.
 */
export async function balanceBeforeInLedger(
    ctx: QueryCtx,
    userId: string,
    accountId: string,
    entry: LedgerEntry,
): Promise<bigint> {
    const namespace = accountNamespace(userId, accountId)
    const bounds = { upper: { key: entry.date, inclusive: false } } as const
    const [outflows, inflows] = await Promise.all([
        outflowsByAccount.sum(ctx, { namespace, bounds }),
        inflowsByAccount.sum(ctx, { namespace, bounds }),
    ])
    let balance = BigInt(Math.round(outflows + inflows))

    const [sourceRows, destRows] = await Promise.all([
        ctx.db
            .query('transactions')
            .withIndex('by_user_account_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('accountId', accountId)
                    .eq('date', entry.date),
            )
            .collect(),
        ctx.db
            .query('transactions')
            .withIndex('by_user_to_account_date', (q) =>
                q
                    .eq('userId', userId)
                    .eq('toAccountId', accountId)
                    .eq('date', entry.date),
            )
            .collect(),
    ])
    const sameDate = new Map<string, Doc<'transactions'>>()
    for (const row of [...sourceRows, ...destRows]) sameDate.set(row.id, row)
    for (const row of sameDate.values()) {
        if (row.id !== entry.id && isBeforeInLedger(row, entry)) {
            balance += ledgerDelta(row, accountId)
        }
    }
    return balance
}

/** The first live adjustment on `accountId` after `entry` in ledger order. */
async function nextAdjustmentAfter(
    ctx: MutationCtx,
    userId: string,
    accountId: string,
    entry: LedgerEntry,
): Promise<Doc<'transactions'> | null> {
    const candidates = ctx.db
        .query('transactions')
        .withIndex('by_user_account_type_archived_date', (q) =>
            q
                .eq('userId', userId)
                .eq('accountId', accountId)
                .eq('type', 'balance_adjustment')
                .eq('isArchived', false)
                .gte('date', entry.date),
        )
    for await (const adjustment of candidates) {
        if (adjustment.id === entry.id) continue
        if (isBeforeInLedger(entry, adjustment)) return adjustment
    }
    return null
}

/**
 * Re-derives one adjustment's amount from the ledger before it. Writes only
 * when the amount actually moved, with a fresh `seq` so every device pulls
 * the new amount — including the one whose push triggered it, since a push
 * acks its own `seq` and would otherwise never see the correction.
 *
 * Returns the change it made, or null when the amount was already right.
 */
export async function reconcileAdjustment(
    ctx: MutationCtx,
    adjustment: Doc<'transactions'>,
): Promise<{ from: bigint; to: bigint } | null> {
    const previous = await balanceBeforeInLedger(
        ctx,
        adjustment.userId,
        adjustment.accountId,
        adjustment,
    )
    const amount = adjustmentAmount(
        adjustment.balanceAfter ?? previous,
        previous,
    )
    if (amount === adjustment.amount) return null

    const seq = await nextSeq(ctx, adjustment.userId)
    await ctx.db.patch(adjustment._id, {
        amount,
        updatedAt: BigInt(Date.now()),
        seq,
    })
    const change = { from: adjustment.amount, to: amount }
    const updated = await ctx.db.get(adjustment._id)
    if (!updated) return change
    // Only the amount moved, and the tag aggregate is keyed by date alone.
    // Not `aggregateReplace`: when every adjustment was consistent before the
    // write, re-deriving this one puts the balance after it back on
    // `balanceAfter` — what later adjustments were already measured against —
    // so there is nothing further to reconcile. Data that was never
    // reconciled does not meet that precondition: fixing it has to walk each
    // account's adjustments in ledger order.
    await outflowsByAccount.replace(ctx, adjustment, updated)
    await inflowsByAccount.replace(ctx, adjustment, updated)
    return change
}

/**
 * Keeps every balance adjustment's declaration true after one transaction
 * changed. `oldDoc` is the row before the write (null on insert), `newDoc`
 * after it (null on hard delete); call after the aggregates are updated.
 *
 * Re-derives the first adjustment after the old position and after the new
 * one on every account either touches, plus the row itself when it is an
 * adjustment. They are reconciled in ledger order, each re-read first, so a
 * later one is measured against the earlier one's corrected amount.
 */
export async function reconcileAfterLedgerChange(
    ctx: MutationCtx,
    oldDoc: Doc<'transactions'> | null,
    newDoc: Doc<'transactions'> | null,
): Promise<void> {
    if (oldDoc && newDoc && !ledgerChanged(oldDoc, newDoc)) return

    const affected = new Map<string, Doc<'transactions'>>()
    if (newDoc && !newDoc.isArchived && newDoc.type === 'balance_adjustment') {
        affected.set(newDoc.id, newDoc)
    }
    for (const doc of [oldDoc, newDoc]) {
        if (!doc || doc.isArchived) continue
        for (const accountId of touchedAccounts(doc)) {
            const next = await nextAdjustmentAfter(
                ctx,
                doc.userId,
                accountId,
                doc,
            )
            if (next) affected.set(next.id, next)
        }
    }

    const ordered = [...affected.values()].sort(compareLedgerOrder)
    for (const stale of ordered) {
        const adjustment = await ctx.db.get(stale._id)
        if (!adjustment || adjustment.isArchived) continue
        await reconcileAdjustment(ctx, adjustment)
    }
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
