import 'dart:convert';

import 'package:app/components/dashboard/dashboard_background.dart';
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

/// The dashboard grid is this many columns wide. Widths map onto a whole
/// number of these units (see [DashboardWidthUnits]).
const int dashboardGridUnits = 6;

/// How many grid units each width spans. `third` = 2, `half` = 3,
/// `twoThirds` = 4, `full` = 6 (the whole [dashboardGridUnits] grid).
extension DashboardWidthUnits on DashboardWidth {
  int get units => switch (this) {
    DashboardWidth.full => dashboardGridUnits,
    DashboardWidth.twoThirds => 4,
    DashboardWidth.half => 3,
    DashboardWidth.third => 2,
  };
}

/// The widest width that fits within [maxUnits] grid units, or null when not
/// even the narrowest width ([DashboardWidth.third]) fits (a 1-unit leftover).
DashboardWidth? dashboardWidthForUnits(int maxUnits) {
  for (final width in DashboardWidth.values) {
    if (width.units <= maxUnits) return width;
  }
  return null;
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
  const DashboardWidgetSpec({
    required this.width,
    this.background = DashboardBackgroundStyle.none,
  });

  final DashboardWidth width;
  final DashboardBackgroundStyle background;
}

/// A Stat block: one number reduced from the transactions matching [filter]
/// via [aggregation]. For sum/net, [filter] should carry a currency scope.
class StatWidgetSpec extends DashboardWidgetSpec {
  const StatWidgetSpec({
    required this.title,
    required this.filter,
    required this.aggregation,
    super.background,
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
    super.background,
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
    super.background,
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
    super.background,
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
  final rawTitle = options['title'];
  final title = rawTitle is String ? rawTitle : '';
  final background = DashboardBackgroundStyle.fromJson(options['background']);

  switch (type) {
    case WidgetType.stat:
      return StatWidgetSpec(
        title: title,
        filter: dashboardFilterFromRow(row, filtersById),
        aggregation: _statAggregationFromName(options['aggregation']),
        background: background,
        width: width ?? DashboardWidth.third,
      );
    case WidgetType.list:
      final rawLimit = options['limit'];
      return TransactionListWidgetSpec(
        title: title,
        filter: dashboardFilterFromRow(row, filtersById),
        limit: rawLimit is num && rawLimit.isFinite && rawLimit > 0
            ? rawLimit.toInt()
            : 5,
        background: background,
        width: width ?? DashboardWidth.full,
      );
    case WidgetType.balance:
      final rawCurrency = options['currency'];
      return BalanceCardWidgetSpec(
        title: title,
        currency: rawCurrency is String ? rawCurrency : '',
        background: background,
        width: width ?? DashboardWidth.half,
      );
    case WidgetType.chart:
      final rawGroupBy = options['groupBy'];
      final rawChartKind = options['chartKind'];
      return ChartWidgetSpec(
        title: title,
        filter: dashboardFilterFromRow(row, filtersById),
        groupBy:
            BreakdownGroupBy.fromWire(rawGroupBy is String ? rawGroupBy : '') ??
            BreakdownGroupBy.category,
        chartKind:
            BreakdownChartKind.fromWire(
              rawChartKind is String ? rawChartKind : '',
            ) ??
            BreakdownChartKind.pie,
        background: background,
        width: width ?? DashboardWidth.full,
      );
  }
}

/// Serializes a widget's display options to the JSON string stored in
/// `dashboard_widgets.options`. Drops null entries so the stored shape stays
/// minimal per type.
String encodeWidgetOptions(Map<String, Object?> options) {
  final encoded = {...options}..removeWhere((_, value) => value == null);
  return jsonEncode(encoded);
}

Map<String, Object?> _decodeOptions(String raw) {
  if (raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : const <String, Object?>{};
  } on FormatException {
    return const {};
  }
}

/// Merges widget option changes into the existing opaque JSON object.
///
/// Layout and forward-compatible keys must survive content-only edits made by
/// the sheet or the voice agent. Invalid legacy JSON degrades to an empty object
/// and becomes valid again on the next write.
String mergeWidgetOptions(
  String existingOptions,
  Map<String, Object?> changes,
) {
  final merged = {..._decodeOptions(existingOptions)};
  // These keys are owned by the content editor. Remove the old type's shape
  // first so changing type or clearing a background does not retain stale
  // values, while layout and unknown forward-compatible keys survive.
  for (final key in const {
    'title',
    'aggregation',
    'limit',
    'currency',
    'groupBy',
    'chartKind',
    'background',
  }) {
    merged.remove(key);
  }
  merged.addAll(changes);
  return encodeWidgetOptions(merged);
}

/// A widget's manual placement on the dashboard grid: which [row] it sits on
/// (0-based, contiguous) and the starting column [col] (0-based, in grid units,
/// where `col + width.units <= dashboardGridUnits`). Persisted inside the
/// widget's `options` JSON under the `layout` key, so it rides the existing
/// opaque-options sync with no schema change.
class DashboardLayoutCoord {
  const DashboardLayoutCoord({required this.row, required this.col});

  final int row;
  final int col;
}

/// Reads the manual [DashboardLayoutCoord] out of a widget's `options` JSON, or
/// null when absent/malformed. A null means the widget predates manual layout
/// (or was written by an older client); callers derive a coordinate from the
/// legacy auto-flow in that case.
DashboardLayoutCoord? dashboardLayoutFromOptions(String optionsJson) {
  final layout = _decodeOptions(optionsJson)['layout'];
  if (layout is! Map) return null;
  final row = layout['row'];
  final col = layout['col'];
  if (row is! num || col is! num || !row.isFinite || !col.isFinite) return null;
  final rowInt = row.toInt();
  final colInt = col.toInt();
  if (row != rowInt ||
      col != colInt ||
      rowInt < 0 ||
      colInt < 0 ||
      colInt >= dashboardGridUnits) {
    return null;
  }
  return DashboardLayoutCoord(row: rowInt, col: colInt);
}

/// Returns a copy of [optionsJson] with the manual [coord] written under the
/// `layout` key, leaving all other options intact. Used when persisting a move.
String writeDashboardLayout(String optionsJson, DashboardLayoutCoord coord) {
  final options = {..._decodeOptions(optionsJson)};
  options['layout'] = {'row': coord.row, 'col': coord.col};
  return jsonEncode(options);
}

/// Resolves a persisted widget row's saved filter to the transaction filter
/// used by the dashboard display and edit sheet.
TransactionFilter dashboardFilterFromRow(
  DashboardWidget row,
  Map<String, SavedFilter> filtersById,
) {
  final filterId = row.filterId;
  if (filterId == null) return const TransactionFilter();
  final filter = filtersById[filterId];
  if (filter == null) return const TransactionFilter();
  try {
    final decoded = jsonDecode(filter.config);
    if (decoded is! Map) return const TransactionFilter();
    return TransactionFilter.fromCanonicalJson(
      Map<String, Object?>.from(decoded),
    );
  } on Object {
    return const TransactionFilter();
  }
}

StatAggregation _statAggregationFromName(Object? name) {
  for (final agg in StatAggregation.values) {
    if (agg.name == name) return agg;
  }
  return StatAggregation.sum;
}
