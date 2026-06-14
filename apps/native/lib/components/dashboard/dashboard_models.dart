import 'dart:convert';

import 'package:app/data/data.dart';
import 'package:app/database.dart';

/// Tile width within the flat dashboard flow (see docs/home-dashboard.md
/// "Layout: width, not nested rows"). Narrower tiles wrap into rows — three
/// [third]s make a row, [twoThirds] pairs with [third], and [full] spans the
/// whole width. `wire` is the value stored in `dashboard_widgets.width`.
enum DashboardWidth {
  full('full'),
  twoThirds('two_thirds'),
  half('half'),
  third('third');

  const DashboardWidth(this.wire);

  final String wire;

  static DashboardWidth? fromWire(String wire) {
    for (final w in values) {
      if (w.wire == wire) return w;
    }
    return null;
  }
}

/// The persisted widget kinds. `wire` is the value stored in
/// `dashboard_widgets.type`.
enum WidgetType {
  stat('stat'),
  list('list'),
  balance('balance'),
  chart('chart');

  const WidgetType(this.wire);

  final String wire;

  static WidgetType? fromWire(String wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

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

/// A Breakdown chart: the transactions matching [filter] bucketed by [groupBy]
/// and drawn as [chartKind] (pie / bar / line). For a meaningful single-number
/// scale the [filter] should carry a currency scope, like the Stat block.
/// Backed by `SummaryRepository.watchBreakdown`.
class ChartWidgetSpec extends DashboardWidgetSpec {
  const ChartWidgetSpec({
    required this.title,
    required this.filter,
    required this.groupBy,
    required this.chartKind,
    super.width = DashboardWidth.full,
  });

  final String title;
  final TransactionFilter filter;
  final BreakdownGroupBy groupBy;
  final BreakdownChartKind chartKind;
}

/// Resolves a persisted [DashboardWidget] row (plus the saved filters it may
/// reference) into a renderable [DashboardWidgetSpec]. Returns null for an
/// unknown widget type so a forward-compat row written by a newer client is
/// skipped rather than crashing the dashboard.
///
/// A stat/list widget whose `filterId` is null or points at a missing/deleted
/// filter degrades to the empty (match-all) filter instead of disappearing.
DashboardWidgetSpec? dashboardSpecFromRow(
  DashboardWidget row,
  Map<String, SavedFilter> filtersById,
) {
  final type = WidgetType.fromWire(row.type);
  if (type == null) return null;
  final width = DashboardWidth.fromWire(row.width);
  final options = _decodeOptions(row.options);
  final title = options['title'] as String? ?? '';

  switch (type) {
    case WidgetType.stat:
      return StatWidgetSpec(
        title: title,
        filter: _resolveFilter(row.filterId, filtersById),
        aggregation: _statAggregationFromName(options['aggregation']),
        width: width ?? DashboardWidth.third,
      );
    case WidgetType.list:
      return TransactionListWidgetSpec(
        title: title,
        filter: _resolveFilter(row.filterId, filtersById),
        limit: (options['limit'] as num?)?.toInt() ?? 5,
        width: width ?? DashboardWidth.full,
      );
    case WidgetType.balance:
      return BalanceCardWidgetSpec(
        title: title,
        currency: options['currency'] as String? ?? '',
        width: width ?? DashboardWidth.half,
      );
    case WidgetType.chart:
      return ChartWidgetSpec(
        title: title,
        filter: _resolveFilter(row.filterId, filtersById),
        groupBy:
            BreakdownGroupBy.fromWire(options['groupBy'] as String? ?? '') ??
            BreakdownGroupBy.category,
        chartKind:
            BreakdownChartKind.fromWire(
              options['chartKind'] as String? ?? '',
            ) ??
            BreakdownChartKind.pie,
        width: width ?? DashboardWidth.full,
      );
  }
}

/// Serializes a widget's display options to the JSON string stored in
/// `dashboard_widgets.options`. Drops null entries so the stored shape stays
/// minimal per type.
String encodeWidgetOptions(Map<String, Object?> options) {
  options.removeWhere((_, value) => value == null);
  return jsonEncode(options);
}

Map<String, Object?> _decodeOptions(String raw) {
  if (raw.isEmpty) return const {};
  final decoded = jsonDecode(raw);
  return decoded is Map<String, Object?> ? decoded : const {};
}

TransactionFilter _resolveFilter(
  String? filterId,
  Map<String, SavedFilter> filtersById,
) {
  if (filterId == null) return const TransactionFilter();
  final filter = filtersById[filterId];
  if (filter == null) return const TransactionFilter();
  final decoded = jsonDecode(filter.config);
  if (decoded is! Map<String, Object?>) return const TransactionFilter();
  return TransactionFilter.fromCanonicalJson(decoded);
}

StatAggregation _statAggregationFromName(Object? name) {
  for (final agg in StatAggregation.values) {
    if (agg.name == name) return agg;
  }
  return StatAggregation.sum;
}
