/// Typed results for the summary queries. Amounts stay in BigInt cents;
/// serialization to protocol doubles happens at the tool layer.
library;

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.totalCents,
  });

  final String categoryId;
  final String name;
  final BigInt totalCents;
}

class AccountFlow {
  const AccountFlow({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.inCents,
    required this.outCents,
  });

  final String accountId;
  final String name;
  final String currency;
  final BigInt inCents;
  final BigInt outCents;

  BigInt get netCents => inCents - outCents;
}

/// How a Stat-block widget reduces its filtered transactions to one number.
///
/// - [sum] — gross total of the matched amounts (e.g. "spent this month" when
///   the filter is `type=expense`).
/// - [net] — signed cash flow: income `+`, expense `-`, balance adjustments by
///   their stored sign; transfers are excluded (they move money between the
///   user's own accounts, not in/out of net worth — mirrors
///   `SummaryRepository.byCategory`).
/// - [count] — number of matched transactions (currency-agnostic).
enum StatAggregation { sum, net, count }

/// Result of a Stat-block aggregation. [amountCents] is meaningful for
/// [StatAggregation.sum] / [StatAggregation.net]; [count] is always populated.
class StatValue {
  const StatValue({
    required this.aggregation,
    required this.amountCents,
    required this.count,
  });

  final StatAggregation aggregation;
  final BigInt amountCents;
  final int count;
}
