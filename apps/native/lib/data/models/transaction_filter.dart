import 'package:flutter/material.dart' show DateTimeRange;

import '../../shared/dates.dart';

/// Common shape for filter dimension enums stored by their `wire` value.
abstract interface class WireValue {
  String get wire;
}

/// Finds the enum value whose [WireValue.wire] matches [wire], or null.
T? _enumByWire<T extends WireValue>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  return null;
}

/// Transaction type dimension. `wire` matches the value stored in
/// `transactions.type`; `label` is shown in the UI.
enum TxnType implements WireValue {
  expense('expense'),
  income('income'),
  transfer('transfer'),
  balanceAdjustment('balance_adjustment');

  const TxnType(this.wire);

  @override
  final String wire;
}

/// Status dimension. Absence (null on the filter) means "any".
enum TxnStatus implements WireValue {
  pending('pending'),
  cleared('cleared');

  const TxnStatus(this.wire);

  @override
  final String wire;
}

/// Relative date presets, resolved at render time so "this month" rolls
/// forward instead of freezing (see docs/home-dashboard.md).
enum DatePreset implements WireValue {
  today('today'),
  thisWeek('this_week'),
  thisMonth('this_month'),
  lastMonth('last_month'),
  thisYear('this_year');

  const DatePreset(this.wire);

  @override
  final String wire;
}

/// Transfers have a source (`accountId`) and destination (`toAccountId`); the
/// account filter carries which side to match.
enum AccountDirection implements WireValue {
  source('source'),
  destination('destination'),
  either('either');

  const AccountDirection(this.wire);

  @override
  final String wire;
}

/// Whether a transaction must carry *any* of the selected tags or *all* of them.
enum TagMatch implements WireValue {
  any('any'),
  all('all');

  const TagMatch(this.wire);

  @override
  final String wire;
}

/// Resolved date window for queries: `date >= fromMs && date < toExclusiveMs`.
/// Either bound may be null (open-ended).
typedef DateWindow = ({BigInt? fromMs, BigInt? toExclusiveMs});

/// A node in the canonical condition tree stored in `saved_filters.config`.
sealed class FilterNode {
  const FilterNode();

  Map<String, Object?> toJson();

  bool get isEmpty => false;

  bool get containsSubtagExpansion => false;
}

/// A boolean group in the canonical filter tree.
class FilterGroup extends FilterNode {
  const FilterGroup({
    this.combinator = 'and',
    this.not = false,
    this.children = const [],
  });

  final String combinator;
  final bool not;
  final List<FilterNode> children;

  factory FilterGroup.fromJson(Map<String, Object?> json) {
    final rawChildren = json['children'];
    return FilterGroup(
      combinator: json['combinator'] == 'or' ? 'or' : 'and',
      not: json['not'] == true,
      children: rawChildren is List
          ? [
              for (final child in rawChildren)
                if (child is Map) filterNodeFromJson(child),
            ]
          : const [],
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'combinator': combinator == 'or' ? 'or' : 'and',
    if (not) 'not': true,
    'children': children.map((child) => child.toJson()).toList(),
  };

  @override
  bool get isEmpty => children.isEmpty;

  @override
  bool get containsSubtagExpansion =>
      children.any((child) => child.containsSubtagExpansion);

  FilterGroup copyWith({
    String? combinator,
    bool? not,
    List<FilterNode>? children,
  }) {
    return FilterGroup(
      combinator: combinator ?? this.combinator,
      not: not ?? this.not,
      children: children ?? this.children,
    );
  }
}

/// A leaf condition in the canonical filter tree.
class FilterCondition extends FilterNode {
  const FilterCondition({
    required this.field,
    required this.operator,
    required this.value,
    this.direction = AccountDirection.either,
    this.match = TagMatch.any,
    this.includeSubtags = false,
  });

  final String field;
  final String operator;
  final Object? value;
  final AccountDirection direction;
  final TagMatch match;
  final bool includeSubtags;

  factory FilterCondition.fromJson(Map<String, Object?> json) {
    final direction = json['direction'];
    final match = json['match'];
    return FilterCondition(
      field: json['field'] is String ? json['field'] as String : 'type',
      operator: json['operator'] is String ? json['operator'] as String : 'in',
      value: json['value'],
      direction: direction is String
          ? _enumByWire(AccountDirection.values, direction) ??
                AccountDirection.either
          : AccountDirection.either,
      match: match is String
          ? _enumByWire(TagMatch.values, match) ?? TagMatch.any
          : TagMatch.any,
      includeSubtags: json['includeSubtags'] == true,
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'field': field,
    'operator': operator,
    'value': value,
    if (field == 'account') 'direction': direction.wire,
    if (field == 'tag') ...{
      'match': match.wire,
      'includeSubtags': includeSubtags,
    },
  };

  @override
  bool get containsSubtagExpansion => field == 'tag' && includeSubtags;

  FilterCondition copyWith({
    String? field,
    String? operator,
    Object? value,
    AccountDirection? direction,
    TagMatch? match,
    bool? includeSubtags,
  }) {
    return FilterCondition(
      field: field ?? this.field,
      operator: operator ?? this.operator,
      value: value ?? this.value,
      direction: direction ?? this.direction,
      match: match ?? this.match,
      includeSubtags: includeSubtags ?? this.includeSubtags,
    );
  }
}

FilterNode filterNodeFromJson(Map<dynamic, dynamic> json) {
  final typed = Map<String, Object?>.from(json);
  return typed.containsKey('children')
      ? FilterGroup.fromJson(typed)
      : FilterCondition.fromJson(typed);
}

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
    this.advancedRoot,
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

  /// Non-null when the filter is using advanced tree semantics that cannot be
  /// faithfully represented by the flat simple-mode fields.
  final FilterGroup? advancedRoot;

  factory TransactionFilter.advanced(FilterGroup root) {
    if (_isSimplyRepresentable(root)) {
      return TransactionFilter.fromCanonicalJson(root.toJson());
    }
    return TransactionFilter(advancedRoot: root);
  }

  bool get isEmpty {
    final advanced = advancedRoot;
    if (advanced != null) return advanced.isEmpty;
    return types.isEmpty &&
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
  }

  bool get isAdvanced => advancedRoot != null;

  FilterGroup get rootGroup => advancedRoot ?? _simpleRootGroup(this);

  /// Rebuilds a filter from the canonical `{combinator, children}` tree
  /// produced by [toCanonicalJson]. Simply representable trees become flat
  /// filters; nested/OR/NOT trees are preserved as [advancedRoot].
  factory TransactionFilter.fromCanonicalJson(Map<String, Object?> json) {
    final root = FilterGroup.fromJson(json);
    if (!_isSimplyRepresentable(root)) {
      return TransactionFilter.advanced(root);
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

    for (final child in root.children) {
      if (child is! FilterCondition) continue;
      final field = child.field;
      final operator = child.operator;
      final value = child.value;
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
          accountDirection = child.direction;
        case 'category':
          categoryIds.addAll(asStringList(value));
        case 'tag':
          tagIds.addAll(asStringList(value));
          tagMatch = child.match;
          includeSubtags = child.includeSubtags;
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
  /// start on Monday (ISO week convention).
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
      advancedRoot: advancedRoot,
    );
  }

  /// Serializes to the canonical `{combinator, children}` tree from the design
  /// doc. The simple editor only ever produces a single top-level `and`.
  Map<String, Object?> toCanonicalJson() {
    final advanced = advancedRoot;
    if (advanced != null) return advanced.toJson();

    return _simpleRootGroup(this).toJson();
  }
}

FilterGroup _simpleRootGroup(TransactionFilter filter) {
  final children = <Map<String, Object?>>[];

  if (filter.types.isNotEmpty) {
    children.add({
      'field': 'type',
      'operator': 'in',
      'value': filter.types.map((t) => t.wire).toList(),
    });
  }

  if (filter.status != null) {
    children.add({
      'field': 'status',
      'operator': 'in',
      'value': [filter.status!.wire],
    });
  }

  if (filter.dateRange != null) {
    children.add({
      'field': 'date',
      'operator': 'between',
      'value': {
        'from': filter.dateRange!.start.toIso8601String(),
        'to': filter.dateRange!.end.toIso8601String(),
      },
    });
  } else if (filter.datePreset != null) {
    children.add({
      'field': 'date',
      'operator': 'relative',
      'value': filter.datePreset!.wire,
    });
  }

  if (filter.accountIds.isNotEmpty) {
    children.add({
      'field': 'account',
      'operator': 'in',
      'value': filter.accountIds.toList(),
      'direction': filter.accountDirection.wire,
    });
  }

  if (filter.categoryIds.isNotEmpty) {
    children.add({
      'field': 'category',
      'operator': 'in',
      'value': filter.categoryIds.toList(),
    });
  }

  if (filter.tagIds.isNotEmpty) {
    children.add({
      'field': 'tag',
      'operator': 'in',
      'value': filter.tagIds.toList(),
      'match': filter.tagMatch.wire,
      'includeSubtags': filter.includeSubtags,
    });
  }

  if (filter.currency != null) {
    children.add({
      'field': 'currency',
      'operator': 'in',
      'value': [filter.currency],
    });

    if (filter.amountMinCents != null || filter.amountMaxCents != null) {
      children.add({
        'field': 'amount',
        'operator': 'between',
        'value': {'min': filter.amountMinCents, 'max': filter.amountMaxCents},
      });
    }
  }

  final trimmed = filter.search?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    children.add({'field': 'text', 'operator': 'contains', 'value': trimmed});
  }

  return FilterGroup(
    children: children.map((child) => FilterCondition.fromJson(child)).toList(),
  );
}

bool _isSimplyRepresentable(FilterGroup root) {
  if (root.combinator != 'and' || root.not) return false;
  final seen = <String>{};
  for (final child in root.children) {
    if (child is! FilterCondition) return false;
    if (!seen.add(child.field)) return false;
    switch (child.field) {
      case 'type':
      case 'status':
      case 'account':
      case 'category':
      case 'tag':
      case 'currency':
        if (child.operator != 'in') return false;
      case 'date':
        if (child.operator != 'relative' && child.operator != 'between') {
          return false;
        }
      case 'amount':
        if (child.operator != 'between') return false;
      case 'text':
        if (child.operator != 'contains') return false;
      default:
        return false;
    }
  }
  return true;
}
