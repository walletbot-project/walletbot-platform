import 'package:app/data/data.dart';

/// Tile width within the flat dashboard flow (see docs/home-dashboard.md
/// "Layout: width, not nested rows"). Narrower tiles wrap into rows — three
/// [third]s make a row, a [full] spans the whole width.
enum DashboardWidth { full, half, third }

/// One configured dashboard tile. v1 ships only the Stat block; the sealed
/// base lets [DashboardView] switch exhaustively as the remaining widget types
/// (balance card, transaction list, breakdown chart) are added — each new
/// variant forces a compile error at the switch until it is rendered.
sealed class DashboardWidgetSpec {
  const DashboardWidgetSpec({required this.width});

  final DashboardWidth width;
}

/// A Stat block: one number reduced from the transactions matching [filter]
/// via [aggregation]. For sum/net, [filter] should carry a currency scope.
class StatWidgetSpec extends DashboardWidgetSpec {
  const StatWidgetSpec({
    required this.title,
    required this.filter,
    required this.aggregation,
    super.width = DashboardWidth.third,
  });

  final String title;
  final TransactionFilter filter;
  final StatAggregation aggregation;
}

/// A Transaction list: the most recent [limit] rows matching [filter], newest
/// first. Backed by the reactive `TransactionRepository.watch` stream.
class TransactionListWidgetSpec extends DashboardWidgetSpec {
  const TransactionListWidgetSpec({
    required this.title,
    required this.filter,
    this.limit = 5,
    super.width = DashboardWidth.full,
  });

  final String title;
  final TransactionFilter filter;
  final int limit;
}

/// A Balance card: the live total balance across all accounts in [currency]
/// "as of now" (not date-bounded). Backed by
/// `AccountRepository.watchBalanceForCurrency`.
class BalanceCardWidgetSpec extends DashboardWidgetSpec {
  const BalanceCardWidgetSpec({
    required this.title,
    required this.currency,
    super.width = DashboardWidth.half,
  });

  final String title;
  final String currency;
}
