/// Exchange-rate rule — single source of truth for cross-currency transfers on
/// native. The stored rate is always >= 1, expressed as the larger amount
/// divided by the smaller one (i.e. how many units of the weaker currency equal
/// one unit of the stronger one). The two amounts must be in the same unit
/// (both cents or both whole units) — the result is a pure ratio, so the unit
/// cancels out.
///
/// The direction (which currency is the base) is not stored: it is recovered at
/// display time by comparing the source amount vs the destination amount.
///
/// Mirror of packages/shared/src/exchange-rate.ts (kept in sync manually since
/// Dart can't import TS).
double? computeExchangeRate(double amount, double toAmount) {
  if (amount <= 0 || toAmount <= 0) return null;
  return amount > toAmount ? amount / toAmount : toAmount / amount;
}
