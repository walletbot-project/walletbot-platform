import 'package:flutter/material.dart' show DateTimeRange;

import '../../shared/dates.dart';

/// Common shape for the filter dimension enums: a stored/query `wire` value and
/// a Spanish UI `label`. Lets [TransactionFilter.fromCanonicalJson] look any of
/// them up by wire value generically.
abstract interface class WireLabeled {
  String get wire;
  String get label;
}

/// Finds the enum value whose [WireLabeled.wire] matches [wire], or null.
T? _enumByWire<T extends WireLabeled>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  return null;
}

/// Transaction type dimension. `wire` matches the value stored in
/// `transactions.type`; `label` is shown in the UI.
enum TxnType implements WireLabeled {
  expense('expense', 'Gastos'),
  income('income', 'Ingresos'),
  transfer('transfer', 'Transferencias'),
  balanceAdjustment('balance_adjustment', 'Ajustes');

  const TxnType(this.wire, this.label);

  @override
  final String wire;
  @override
  final String label;
}

/// Status dimension. Absence (null on the filter) means "any".
enum TxnStatus implements WireLabeled {
  pending('pending', 'Pendiente'),
  cleared('cleared', 'Confirmado');

  const TxnStatus(this.wire, this.label);

  @override
  final String wire;
  @override
  final String label;
}

/// Relative date presets, resolved at render time so "this month" rolls
/// forward instead of freezing (see docs/home-dashboard.md).
enum DatePreset implements WireLabeled {
  today('today', 'Hoy'),
  thisWeek('this_week', 'Esta semana'),
  thisMonth('this_month', 'Este mes'),
  lastMonth('last_month', 'Mes pasado'),
  thisYear('this_year', 'Este año');

  const DatePreset(this.wire, this.label);

  @override
  final String wire;
  @override
  final String label;
}

/// Transfers have a source (`accountId`) and destination (`toAccountId`); the
/// account filter carries which side to match.
enum AccountDirection implements WireLabeled {
  source('source', 'Origen'),
  destination('destination', 'Destino'),
  either('either', 'Cualquiera');

  const AccountDirection(this.wire, this.label);

  @override
  final String wire;
  @override
  final String label;
}

/// Whether a transaction must carry *any* of the selected tags or *all* of them.
enum TagMatch implements WireLabeled {
  any('any', 'Cualquiera'),
  all('all', 'Todas');

  const TagMatch(this.wire, this.label);

  @override
  final String wire;
  @override
  final String label;
}

/// Resolved date window for queries: `date >= fromMs && date < toExclusiveMs`.
/// Either bound may be null (open-ended).
typedef DateWindow = ({BigInt? fromMs, BigInt? toExclusiveMs});

/// The simple-mode view over the canonical condition tree described in
/// docs/home-dashboard.md. Every field is optional; an empty filter matches
/// all transactions. [toCanonicalJson] serializes to the stored tree shape.
class TransactionFilter {
  const TransactionFilter({
    this.types = const {},
    this.status,
    this.datePreset,
    this.dateRange,
    this.accountIds = const {},
    this.accountDirection = AccountDirection.either,
    this.categoryIds = const {},
    this.tagIds = const {},
    this.tagMatch = TagMatch.any,
    this.includeSubtags = false,
    this.currency,
    this.amountMinCents,
    this.amountMaxCents,
    this.search,
  });

  final Set<TxnType> types;
  final TxnStatus? status;

  /// Relative preset. Ignored when [dateRange] is set (absolute wins).
  final DatePreset? datePreset;

  /// Absolute range. Takes precedence over [datePreset].
  final DateTimeRange? dateRange;

  final Set<String> accountIds;
  final AccountDirection accountDirection;
  final Set<String> categoryIds;

  final Set<String> tagIds;
  final TagMatch tagMatch;
  final bool includeSubtags;

  /// Single currency scope. Required for the amount dimension to apply.
  final String? currency;
  final int? amountMinCents;
  final int? amountMaxCents;

  final String? search;

  bool get isEmpty =>
      types.isEmpty &&
      status == null &&
      datePreset == null &&
      dateRange == null &&
      accountIds.isEmpty &&
      categoryIds.isEmpty &&
      tagIds.isEmpty &&
      currency == null &&
      amountMinCents == null &&
      amountMaxCents == null &&
      (search == null || search!.trim().isEmpty);

  /// Rebuilds a filter from the canonical `{combinator, children}` tree
  /// produced by [toCanonicalJson]. Only the simple-mode subset is understood:
  /// a single top-level `and` of flat conditions. Anything else (nested groups,
  /// `or`, `not`, unknown fields/operators) is skipped, so an advanced filter
  /// degrades to the conditions it can represent rather than throwing.
  factory TransactionFilter.fromCanonicalJson(Map<String, Object?> json) {
    final children = json['children'];
    if (json['combinator'] != 'and' || children is! List) {
      return const TransactionFilter();
    }

    final types = <TxnType>{};
    TxnStatus? status;
    DatePreset? datePreset;
    DateTimeRange? dateRange;
    final accountIds = <String>{};
    var accountDirection = AccountDirection.either;
    final categoryIds = <String>{};
    final tagIds = <String>{};
    var tagMatch = TagMatch.any;
    var includeSubtags = false;
    String? currency;
    int? amountMinCents;
    int? amountMaxCents;
    String? search;

    List<String> asStringList(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];

    for (final raw in children) {
      if (raw is! Map) continue;
      final field = raw['field'];
      final operator = raw['operator'];
      final value = raw['value'];
      switch (field) {
        case 'type':
          for (final wire in asStringList(value)) {
            final t = _enumByWire(TxnType.values, wire);
            if (t != null) types.add(t);
          }
        case 'status':
          final wire = asStringList(value).firstOrNull;
          if (wire != null) status = _enumByWire(TxnStatus.values, wire);
        case 'date':
          if (operator == 'relative' && value is String) {
            datePreset = _enumByWire(DatePreset.values, value);
          } else if (operator == 'between' && value is Map) {
            final from = value['from'];
            final to = value['to'];
            if (from is String && to is String) {
              final start = DateTime.tryParse(from);
              final end = DateTime.tryParse(to);
              if (start != null && end != null) {
                dateRange = DateTimeRange(start: start, end: end);
              }
            }
          }
        case 'account':
          accountIds.addAll(asStringList(value));
          final dir = raw['direction'];
          if (dir is String) {
            accountDirection =
                _enumByWire(AccountDirection.values, dir) ?? accountDirection;
          }
        case 'category':
          categoryIds.addAll(asStringList(value));
        case 'tag':
          tagIds.addAll(asStringList(value));
          final match = raw['match'];
          if (match is String) {
            tagMatch = _enumByWire(TagMatch.values, match) ?? tagMatch;
          }
          includeSubtags = raw['includeSubtags'] == true;
        case 'currency':
          currency = asStringList(value).firstOrNull;
        case 'amount':
          if (value is Map) {
            final min = value['min'];
            final max = value['max'];
            if (min is int) amountMinCents = min;
            if (max is int) amountMaxCents = max;
          }
        case 'text':
          if (value is String) search = value;
      }
    }

    return TransactionFilter(
      types: types,
      status: status,
      datePreset: datePreset,
      dateRange: dateRange,
      accountIds: accountIds,
      accountDirection: accountDirection,
      categoryIds: categoryIds,
      tagIds: tagIds,
      tagMatch: tagMatch,
      includeSubtags: includeSubtags,
      currency: currency,
      amountMinCents: amountMinCents,
      amountMaxCents: amountMaxCents,
      search: search,
    );
  }

  /// Resolves the date dimension to an absolute window at query time.
  /// [dateRange] bounds are day-precision: the end day is inclusive. Weeks
  /// start on Monday (the app's Spanish locale convention).
  DateWindow? resolveDateWindow({DateTime? now}) {
    final range = dateRange;
    if (range != null) {
      return (
        fromMs: epochMs(dayStart(range.start)),
        toExclusiveMs: endOfDayExclusiveMs(range.end),
      );
    }
    final preset = datePreset;
    if (preset == null) return null;
    final ref = now ?? DateTime.now();
    final today = dayStart(ref);
    switch (preset) {
      case DatePreset.today:
        return (
          fromMs: epochMs(today),
          toExclusiveMs: endOfDayExclusiveMs(today),
        );
      case DatePreset.thisWeek:
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return (
          fromMs: epochMs(weekStart),
          toExclusiveMs: epochMs(weekStart.add(const Duration(days: 7))),
        );
      case DatePreset.thisMonth:
        return (
          fromMs: epochMs(DateTime(ref.year, ref.month, 1)),
          toExclusiveMs: epochMs(DateTime(ref.year, ref.month + 1, 1)),
        );
      case DatePreset.lastMonth:
        return (
          fromMs: epochMs(DateTime(ref.year, ref.month - 1, 1)),
          toExclusiveMs: epochMs(DateTime(ref.year, ref.month, 1)),
        );
      case DatePreset.thisYear:
        return (
          fromMs: epochMs(DateTime(ref.year, 1, 1)),
          toExclusiveMs: epochMs(DateTime(ref.year + 1, 1, 1)),
        );
    }
  }

  TransactionFilter copyWith({
    Set<TxnType>? types,
    TxnStatus? status,
    bool clearStatus = false,
    DatePreset? datePreset,
    bool clearDatePreset = false,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    Set<String>? accountIds,
    AccountDirection? accountDirection,
    Set<String>? categoryIds,
    Set<String>? tagIds,
    TagMatch? tagMatch,
    bool? includeSubtags,
    String? currency,
    bool clearCurrency = false,
    int? amountMinCents,
    bool clearAmountMin = false,
    int? amountMaxCents,
    bool clearAmountMax = false,
    String? search,
  }) {
    return TransactionFilter(
      types: types ?? this.types,
      status: clearStatus ? null : (status ?? this.status),
      datePreset: clearDatePreset ? null : (datePreset ?? this.datePreset),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      accountIds: accountIds ?? this.accountIds,
      accountDirection: accountDirection ?? this.accountDirection,
      categoryIds: categoryIds ?? this.categoryIds,
      tagIds: tagIds ?? this.tagIds,
      tagMatch: tagMatch ?? this.tagMatch,
      includeSubtags: includeSubtags ?? this.includeSubtags,
      currency: clearCurrency ? null : (currency ?? this.currency),
      amountMinCents: clearAmountMin
          ? null
          : (amountMinCents ?? this.amountMinCents),
      amountMaxCents: clearAmountMax
          ? null
          : (amountMaxCents ?? this.amountMaxCents),
      search: search ?? this.search,
    );
  }

  /// Serializes to the canonical `{combinator, children}` tree from the design
  /// doc. The simple editor only ever produces a single top-level `and`.
  Map<String, Object?> toCanonicalJson() {
    final children = <Map<String, Object?>>[];

    if (types.isNotEmpty) {
      children.add({
        'field': 'type',
        'operator': 'in',
        'value': types.map((t) => t.wire).toList(),
      });
    }

    if (status != null) {
      children.add({
        'field': 'status',
        'operator': 'in',
        'value': [status!.wire],
      });
    }

    if (dateRange != null) {
      children.add({
        'field': 'date',
        'operator': 'between',
        'value': {
          'from': dateRange!.start.toIso8601String(),
          'to': dateRange!.end.toIso8601String(),
        },
      });
    } else if (datePreset != null) {
      children.add({
        'field': 'date',
        'operator': 'relative',
        'value': datePreset!.wire,
      });
    }

    if (accountIds.isNotEmpty) {
      children.add({
        'field': 'account',
        'operator': 'in',
        'value': accountIds.toList(),
        'direction': accountDirection.wire,
      });
    }

    if (categoryIds.isNotEmpty) {
      children.add({
        'field': 'category',
        'operator': 'in',
        'value': categoryIds.toList(),
      });
    }

    if (tagIds.isNotEmpty) {
      children.add({
        'field': 'tag',
        'operator': 'in',
        'value': tagIds.toList(),
        'match': tagMatch.wire,
        'includeSubtags': includeSubtags,
      });
    }

    if (currency != null) {
      children.add({
        'field': 'currency',
        'operator': 'in',
        'value': [currency],
      });

      if (amountMinCents != null || amountMaxCents != null) {
        children.add({
          'field': 'amount',
          'operator': 'between',
          'value': {'min': amountMinCents, 'max': amountMaxCents},
        });
      }
    }

    final trimmed = search?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      children.add({'field': 'text', 'operator': 'contains', 'value': trimmed});
    }

    return {'combinator': 'and', 'children': children};
  }
}
