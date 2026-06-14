import 'package:flutter/material.dart' show DateTimeRange;

import '../../shared/dates.dart';

/// Transaction type dimension. `wire` matches the value stored in
/// `transactions.type`; `label` is shown in the UI.
enum TxnType {
  expense('expense', 'Gastos'),
  income('income', 'Ingresos'),
  transfer('transfer', 'Transferencias'),
  balanceAdjustment('balance_adjustment', 'Ajustes');

  const TxnType(this.wire, this.label);

  final String wire;
  final String label;
}

/// Status dimension. Absence (null on the filter) means "any".
enum TxnStatus {
  pending('pending', 'Pendiente'),
  cleared('cleared', 'Confirmado');

  const TxnStatus(this.wire, this.label);

  final String wire;
  final String label;
}

/// Relative date presets, resolved at render time so "this month" rolls
/// forward instead of freezing (see docs/home-dashboard.md).
enum DatePreset {
  today('today', 'Hoy'),
  thisWeek('this_week', 'Esta semana'),
  thisMonth('this_month', 'Este mes'),
  lastMonth('last_month', 'Mes pasado'),
  thisYear('this_year', 'Este año');

  const DatePreset(this.wire, this.label);

  final String wire;
  final String label;
}

/// Transfers have a source (`accountId`) and destination (`toAccountId`); the
/// account filter carries which side to match.
enum AccountDirection {
  source('source', 'Origen'),
  destination('destination', 'Destino'),
  either('either', 'Cualquiera');

  const AccountDirection(this.wire, this.label);

  final String wire;
  final String label;
}

/// Whether a transaction must carry *any* of the selected tags or *all* of them.
enum TagMatch {
  any('any', 'Cualquiera'),
  all('all', 'Todas');

  const TagMatch(this.wire, this.label);

  final String wire;
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
