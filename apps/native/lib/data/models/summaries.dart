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

/// How a Breakdown chart buckets its filtered transactions. `wire` is the value
/// stored in `dashboard_widgets.options.groupBy`.
///
/// - [category] — one bucket per category (transfers excluded, like
///   [CategoryTotal]); the natural "where did my money go" view.
/// - [account] — one bucket per (source) account.
/// - [month] — one bucket per calendar month, the natural time series.
enum BreakdownGroupBy {
  category('category'),
  account('account'),
  month('month');

  const BreakdownGroupBy(this.wire);

  final String wire;

  static BreakdownGroupBy? fromWire(String wire) {
    for (final g in values) {
      if (g.wire == wire) return g;
    }
    return null;
  }
}

/// How a Breakdown chart renders its [BreakdownSlice]s. `wire` is the value
/// stored in `dashboard_widgets.options.chartKind`.
enum BreakdownChartKind {
  pie('pie'),
  bar('bar'),
  line('line');

  const BreakdownChartKind(this.wire);

  final String wire;

  static BreakdownChartKind? fromWire(String wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// One labeled bucket of a breakdown aggregation: a magnitude ([totalCents],
/// always non-negative — sum of absolute amounts) under a display [label], with
/// an optional [colorHex] taken from the grouped entity (category/account) for
/// charts that color their slices. [key] is the stable group key (categoryId /
/// accountId / `YYYY-MM`) used for ordering and chart x-positions.
class BreakdownSlice {
  const BreakdownSlice({
    required this.key,
    required this.label,
    required this.totalCents,
    this.colorHex,
  });

  final String key;
  final String label;
  final BigInt totalCents;
  final String? colorHex;
}
