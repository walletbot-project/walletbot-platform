import type { TxnType } from './dashboard/filter'

/**
 * A balance adjustment is a declaration — "right now this account holds
 * `balanceAfter`" — not a movement of a fixed amount. `balanceAfter` is what
 * the user declared and is never modified; `amount` is only the difference
 * between that declaration and what the platform computed for the account at
 * that moment, and it is derived, never entered.
 *
 * Because `amount` is derived from the past, it changes whenever the past
 * does: recording, editing or deleting a movement dated before an adjustment
 * must re-derive that adjustment's `amount` so the declaration still holds.
 * Movements dated after it never touch it.
 *
 * An adjustment pins the balance, so a change only reaches the **first**
 * adjustment after it on the same account: every later adjustment starts from
 * a balance the earlier one already fixed.
 *
 * This module is the single definition of that rule. The backend applies it
 * incrementally (first adjustment after a write); native replays it in
 * `apps/native/lib/sync/sync_recompute.dart`. Both must agree with
 * `balance-adjustment-fixtures.json` — a disagreement makes the two sides
 * rewrite each other's amounts on every sync.
 */
export type LedgerEntry = {
    id: string
    type: TxnType
    accountId: string
    /** Transfers only: the destination account. */
    toAccountId?: string
    /** Cents. Signed only on adjustments; positive on every other type. */
    amount: bigint
    /** Transfers only: cents credited to the destination account. */
    toAmount?: bigint
    /** Adjustments only: the declared balance, in cents. */
    balanceAfter?: bigint
    /** Ms since epoch. */
    date: bigint
    createdAt: bigint
    isArchived: boolean
}

/**
 * Signed effect of an entry on `accountId`'s balance. An entry touches the
 * account as its source (`accountId`) or, for transfers, as the destination
 * (`toAccountId`). Archived entries have no effect.
 */
export function ledgerDelta(entry: LedgerEntry, accountId: string): bigint {
    if (entry.isArchived) return 0n
    let delta = 0n
    if (entry.accountId === accountId) {
        switch (entry.type) {
            case 'expense':
            case 'transfer':
                delta -= entry.amount
                break
            case 'income':
            case 'balance_adjustment':
                delta += entry.amount
                break
        }
    }
    if (entry.type === 'transfer' && entry.toAccountId === accountId) {
        delta += entry.toAmount ?? entry.amount
    }
    return delta
}

/**
 * Ledger order: by date; at the exact same date, every other movement comes
 * before an adjustment, so the adjustment observes it; then by creation, then
 * by id so the order is total.
 *
 * Movements are ordered by their own date and nothing else. One recorded
 * "today" without a time is dated when it was recorded, which puts it after
 * an adjustment declared earlier today; moving it before the adjustment is up
 * to the user, by editing its time.
 */
export function compareLedgerOrder(a: LedgerEntry, b: LedgerEntry): number {
    if (a.date !== b.date) return a.date < b.date ? -1 : 1
    const aAdj = a.type === 'balance_adjustment'
    const bAdj = b.type === 'balance_adjustment'
    if (aAdj !== bAdj) return aAdj ? 1 : -1
    if (a.createdAt !== b.createdAt) return a.createdAt < b.createdAt ? -1 : 1
    if (a.id === b.id) return 0
    return a.id < b.id ? -1 : 1
}

/** True when `entry` sits before `adjustment` in ledger order. */
export function isBeforeInLedger(
    entry: LedgerEntry,
    adjustment: LedgerEntry,
): boolean {
    return compareLedgerOrder(entry, adjustment) < 0
}

/** The amount that makes an adjustment land on its declared balance. */
export function adjustmentAmount(
    balanceAfter: bigint,
    previousBalance: bigint,
): bigint {
    return balanceAfter - previousBalance
}

/**
 * What the platform computed for the account just before the adjustment —
 * the figure shown next to the declared one. Derived from the stored pair, so
 * it follows `amount` whenever the past changes.
 */
export function adjustmentPreviousBalance(adjustment: {
    amount: bigint
    balanceAfter: bigint
}): bigint {
    return adjustment.balanceAfter - adjustment.amount
}

/**
 * Replays every account in ledger order and returns the correct `amount` of
 * every live adjustment, keyed by id. The reference implementation of the
 * rule: incremental implementations must produce the same amounts.
 *
 * An adjustment without `balanceAfter` declares whatever the balance already
 * was, so its amount is zero.
 */
export function reconcileAdjustments(
    entries: readonly LedgerEntry[],
): Map<string, bigint> {
    const accountIds = new Set<string>()
    for (const e of entries) {
        if (e.isArchived) continue
        accountIds.add(e.accountId)
        if (e.type === 'transfer' && e.toAccountId)
            accountIds.add(e.toAccountId)
    }

    const ordered = entries
        .filter((e) => !e.isArchived)
        .sort(compareLedgerOrder)
    const amounts = new Map<string, bigint>()
    for (const accountId of accountIds) {
        let balance = 0n
        for (const e of ordered) {
            if (e.type === 'balance_adjustment' && e.accountId === accountId) {
                const amount = adjustmentAmount(
                    e.balanceAfter ?? balance,
                    balance,
                )
                amounts.set(e.id, amount)
                balance += amount
                continue
            }
            balance += ledgerDelta(e, accountId)
        }
    }
    return amounts
}
