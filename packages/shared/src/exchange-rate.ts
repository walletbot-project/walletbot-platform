// Exchange-rate rule — single source of truth for cross-currency transfers.
// The stored rate is always >= 1, expressed as the larger amount divided by the
// smaller one (i.e. how many units of the weaker currency equal one unit of the
// stronger one). The two amounts must be in the same unit (both cents or both
// whole units) — the result is a pure ratio, so the unit cancels out.
//
// The direction (which currency is the base) is not stored: it is recovered at
// display time by comparing `amount` vs `toAmount`.
//
// The native app (apps/native/lib/transactions/exchange_rate.dart) keeps its
// own Dart copy of this rule in sync manually since it can't import TS.
export function computeExchangeRate(
    amount: number,
    toAmount: number,
): number | undefined {
    if (amount <= 0 || toAmount <= 0) return undefined
    return amount > toAmount ? amount / toAmount : toAmount / amount
}
