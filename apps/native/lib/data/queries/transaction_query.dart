import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../database.dart';
import '../occurrence.dart';
import '../models/summaries.dart';
import '../models/transaction_filter.dart';

/// Result ordering for transaction lists. The activity screen orders strictly
/// by creation time (newest first) so day headers stay contiguous; the agent
/// orders by the (possibly estimated) transaction date.
/// `dateAsc` is the upcoming list's ordering: soonest first, because
/// nothing there has happened yet.
enum TxnOrdering { createdAtDesc, dateDesc, dateAsc }

/// Expands the filter's tag selection into match groups against the active
/// tag set: one group per selected tag, containing the tag itself plus all
/// its descendants when `includeSubtags` is on.
///
/// [TagMatch.any] → transaction must carry a tag from the union of groups.
/// [TagMatch.all] → transaction must carry a tag from *every* group.
List<Set<String>> expandTagGroups(
  TransactionFilter filter,
  List<Tag> activeTags,
) {
  if (filter.tagIds.isEmpty) return const [];
  if (!filter.includeSubtags) {
    return [
      for (final id in filter.tagIds) {id},
    ];
  }
  final childrenByParent = <String, List<String>>{};
  for (final tag in activeTags) {
    final parentId = tag.parentId;
    if (parentId != null) {
      childrenByParent.putIfAbsent(parentId, () => []).add(tag.id);
    }
  }
  return [
    for (final id in filter.tagIds)
      () {
        final group = <String>{id};
        final queue = <String>[id];
        while (queue.isNotEmpty) {
          final next = queue.removeAt(0);
          for (final childId in childrenByParent[next] ?? const <String>[]) {
            if (group.add(childId)) queue.add(childId);
          }
        }
        return group;
      }(),
  ];
}

/// The single place a [TransactionFilter] becomes SQL — shared by the
/// activity screen and the agent's listTransactions so filter semantics can
/// never diverge. Pure, synchronous query construction — tag groups must be
/// pre-expanded (see [expandTagGroups]; the expansion needs the tags table
/// and happens in `TransactionRepository`).
///
/// [exactFromMs]/[exactToInclusiveMs] are precise inclusive timestamp bounds
/// applied on top of the filter's day-precision date window.
SimpleSelectStatement<$TransactionsTable, Transaction> buildTransactionQuery(
  AppDatabase db,
  TransactionFilter filter, {
  required List<Set<String>> tagGroups,
  List<Tag> activeTags = const [],
  int? limit,
  TxnOrdering ordering = TxnOrdering.createdAtDesc,
  DateTime? now,
  BigInt? exactFromMs,
  BigInt? exactToInclusiveMs,
  TxnOccurrence occurrence = TxnOccurrence.occurred,
}) {
  final query = db.select(db.transactions)
    ..where((t) => t.archived.equals(false));

  // Defaulting to `occurred` is deliberate: every existing caller answers a
  // question about what happened, so the safe side is the one you get by not
  // thinking about it. Wanting the scheduled rows is the exceptional case and
  // has to be asked for.
  query.where((t) => occurrenceFilter(t, occurrence, now: now));

  final advancedRoot = filter.advancedRoot;
  if (advancedRoot != null) {
    query.where(
      (t) => _compileFilterNode(
        db,
        t,
        advancedRoot,
        activeTags: activeTags,
        now: now,
      ),
    );
  } else {
    _applySimpleFilter(db, query, filter, tagGroups: tagGroups, now: now);
  }

  // Exact-millisecond bounds (both inclusive), used by the agent tools whose
  // dates are precise timestamps rather than day ranges.
  if (exactFromMs != null) {
    final from = exactFromMs;
    query.where((t) => t.date.isBiggerOrEqualValue(from));
  }
  if (exactToInclusiveMs != null) {
    final to = exactToInclusiveMs;
    query.where((t) => t.date.isSmallerOrEqualValue(to));
  }

  switch (ordering) {
    case TxnOrdering.createdAtDesc:
      query.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    case TxnOrdering.dateDesc:
      query.orderBy([(t) => OrderingTerm.desc(t.date)]);
    case TxnOrdering.dateAsc:
      query.orderBy([(t) => OrderingTerm.asc(t.date)]);
  }
  if (limit != null) {
    query.limit(limit);
  }
  return query;
}

void _applySimpleFilter(
  AppDatabase db,
  SimpleSelectStatement<$TransactionsTable, Transaction> query,
  TransactionFilter filter, {
  required List<Set<String>> tagGroups,
  DateTime? now,
}) {
  if (filter.types.isNotEmpty) {
    final wires = filter.types.map((t) => t.wire).toList();
    query.where((t) => t.type.isIn(wires));
  }

  if (filter.status != null) {
    query.where((t) => t.status.equals(filter.status!.wire));
  }

  final search = filter.search?.trim() ?? '';
  if (search.isNotEmpty) {
    final escaped = search.replaceAll('%', '%%').replaceAll('_', '__');
    final pattern = '%${escaped.toLowerCase()}%';
    query.where(
      (t) => t.name.lower().like(pattern) | t.description.lower().like(pattern),
    );
  }

  if (filter.categoryIds.isNotEmpty) {
    final ids = filter.categoryIds.toList();
    query.where((t) => t.categoryId.isIn(ids));
  }

  if (filter.accountIds.isNotEmpty) {
    final ids = filter.accountIds.toList();
    switch (filter.accountDirection) {
      case AccountDirection.source:
        query.where((t) => t.accountId.isIn(ids));
      case AccountDirection.destination:
        query.where((t) => t.toAccountId.isIn(ids));
      case AccountDirection.either:
        query.where((t) => t.accountId.isIn(ids) | t.toAccountId.isIn(ids));
    }
  }

  final window = filter.resolveDateWindow(now: now);
  if (window != null) {
    final fromMs = window.fromMs;
    if (fromMs != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(fromMs));
    }
    final toExclusiveMs = window.toExclusiveMs;
    if (toExclusiveMs != null) {
      query.where((t) => t.date.isSmallerThanValue(toExclusiveMs));
    }
  }

  // One membership subquery per group: `any` produces a single group (union),
  // `all` produces one group per selected tag, ANDed together.
  final effectiveGroups =
      filter.tagMatch == TagMatch.any && tagGroups.isNotEmpty
      ? [tagGroups.expand((g) => g).toSet()]
      : tagGroups;
  for (final group in effectiveGroups) {
    final groupIds = group.toList();
    final taggedTxnIds = db.selectOnly(db.transactionTags)
      ..addColumns([db.transactionTags.transactionId])
      ..where(db.transactionTags.tagId.isIn(groupIds));
    query.where((t) => t.id.isInQuery(taggedTxnIds));
  }

  if (filter.currency != null) {
    query.where((t) => t.currency.equals(filter.currency!));

    // Amount bounds apply only within a single-currency scope (the filter
    // model requires currency for the amount dimension). Raw stored value:
    // sign is carried by `type`, except balance adjustments which may be
    // negative.
    final minCents = filter.amountMinCents;
    if (minCents != null) {
      query.where((t) => t.amount.isBiggerOrEqualValue(BigInt.from(minCents)));
    }
    final maxCents = filter.amountMaxCents;
    if (maxCents != null) {
      query.where((t) => t.amount.isSmallerOrEqualValue(BigInt.from(maxCents)));
    }
  }
}

Expression<bool> _compileFilterNode(
  AppDatabase db,
  $TransactionsTable t,
  FilterNode node, {
  required List<Tag> activeTags,
  DateTime? now,
}) {
  switch (node) {
    case FilterCondition():
      return _compileCondition(db, t, node, activeTags: activeTags, now: now);
    case FilterGroup():
      Expression<bool> expression = const Constant(true);
      if (node.children.isNotEmpty) {
        final compiled = [
          for (final child in node.children)
            _compileFilterNode(db, t, child, activeTags: activeTags, now: now),
        ];
        expression = compiled.first;
        for (final next in compiled.skip(1)) {
          expression = node.combinator == 'or'
              ? expression | next
              : expression & next;
        }
      }
      return node.not ? expression.not() : expression;
  }
}

Expression<bool> _compileCondition(
  AppDatabase db,
  $TransactionsTable t,
  FilterCondition condition, {
  required List<Tag> activeTags,
  DateTime? now,
}) {
  final value = condition.value;
  switch (condition.field) {
    case 'type':
      return _stringSet(t.type, condition.operator, _asStringList(value));
    case 'status':
      return _stringSet(t.status, condition.operator, _asStringList(value));
    case 'category':
      return _stringSet(t.categoryId, condition.operator, _asStringList(value));
    case 'currency':
      return _stringSet(t.currency, condition.operator, _asStringList(value));
    case 'account':
      return _accountCondition(t, condition);
    case 'tag':
      return _tagCondition(db, t, condition, activeTags);
    case 'date':
      return _dateCondition(t, condition, now: now);
    case 'amount':
      return _amountCondition(t, condition);
    case 'text':
      if (value is! String || value.trim().isEmpty) {
        return const Constant(true);
      }
      final escaped = value.trim().replaceAll('%', '%%').replaceAll('_', '__');
      final pattern = '%${escaped.toLowerCase()}%';
      final expression = t.name.lower().like(pattern);
      return condition.operator == 'not contains'
          ? expression.not()
          : expression;
    default:
      return const Constant(true);
  }
}

Expression<bool> _stringSet(
  Expression<String> column,
  String operator,
  List<String> values,
) {
  if (values.isEmpty) return const Constant(true);
  return operator == 'not in' ? column.isNotIn(values) : column.isIn(values);
}

Expression<bool> _accountCondition(
  $TransactionsTable t,
  FilterCondition condition,
) {
  final ids = _asStringList(condition.value);
  if (ids.isEmpty) return const Constant(true);
  Expression<bool> expression;
  switch (condition.direction) {
    case AccountDirection.source:
      expression = t.accountId.isIn(ids);
    case AccountDirection.destination:
      expression = t.toAccountId.isIn(ids);
    case AccountDirection.either:
      expression = t.accountId.isIn(ids) | t.toAccountId.isIn(ids);
  }
  return condition.operator == 'not in' ? expression.not() : expression;
}

Expression<bool> _tagCondition(
  AppDatabase db,
  $TransactionsTable t,
  FilterCondition condition,
  List<Tag> activeTags,
) {
  final ids = _asStringList(condition.value);
  if (ids.isEmpty) return const Constant(true);
  final filter = TransactionFilter(
    tagIds: ids.toSet(),
    tagMatch: condition.match,
    includeSubtags: condition.includeSubtags,
  );
  final tagGroups = expandTagGroups(filter, activeTags);
  final effectiveGroups =
      condition.match == TagMatch.any && tagGroups.isNotEmpty
      ? [tagGroups.expand((g) => g).toSet()]
      : tagGroups;
  Expression<bool> expression = const Constant(true);
  for (final group in effectiveGroups) {
    final taggedTxnIds = db.selectOnly(db.transactionTags)
      ..addColumns([db.transactionTags.transactionId])
      ..where(db.transactionTags.tagId.isIn(group.toList()));
    expression = expression & t.id.isInQuery(taggedTxnIds);
  }
  return condition.operator == 'not in' ? expression.not() : expression;
}

Expression<bool> _dateCondition(
  $TransactionsTable t,
  FilterCondition condition, {
  DateTime? now,
}) {
  DateWindow? window;
  final value = condition.value;
  if (condition.operator == 'relative' && value is String) {
    final preset = _enumByWire(DatePreset.values, value);
    if (preset != null) {
      window = TransactionFilter(
        datePreset: preset,
      ).resolveDateWindow(now: now);
    }
  } else if (condition.operator == 'between' && value is Map) {
    final from = value['from'];
    final to = value['to'];
    if (from is String && to is String) {
      final start = DateTime.tryParse(from);
      final end = DateTime.tryParse(to);
      if (start != null && end != null) {
        window = TransactionFilter(
          dateRange: DateTimeRange(start: start, end: end),
        ).resolveDateWindow(now: now);
      }
    }
  }
  if (window == null) return const Constant(true);
  Expression<bool> expression = const Constant(true);
  final fromMs = window.fromMs;
  if (fromMs != null) {
    expression = expression & t.date.isBiggerOrEqualValue(fromMs);
  }
  final toExclusiveMs = window.toExclusiveMs;
  if (toExclusiveMs != null) {
    expression = expression & t.date.isSmallerThanValue(toExclusiveMs);
  }
  return expression;
}

Expression<bool> _amountCondition(
  $TransactionsTable t,
  FilterCondition condition,
) {
  final value = condition.value;
  if (value is! Map) return const Constant(true);
  Expression<bool> expression = const Constant(true);
  final min = value['min'];
  final max = value['max'];
  if ((condition.operator == 'between' || condition.operator == '>=') &&
      min is int) {
    expression = expression & t.amount.isBiggerOrEqualValue(BigInt.from(min));
  }
  if ((condition.operator == 'between' || condition.operator == '<=') &&
      max is int) {
    expression = expression & t.amount.isSmallerOrEqualValue(BigInt.from(max));
  }
  return expression;
}

T? _enumByWire<T extends WireValue>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  return null;
}

List<String> _asStringList(Object? value) {
  return value is List ? value.whereType<String>().toList() : const [];
}

/// THE canonical reactive filtered-transaction stream — reactive to local
/// writes, agent writes, and sync merges. When the filter uses
/// `includeSubtags`, the tag expansion re-resolves when the tag tree changes
/// (so adding a child tag updates open lists/widgets). Both
/// `TransactionRepository.watch` and `SummaryRepository.watchStat` delegate
/// here so filter semantics can never diverge between a list and its summary.
Stream<List<Transaction>> watchFilteredTransactions(
  AppDatabase db,
  TransactionFilter filter, {
  int? limit,
  TxnOrdering ordering = TxnOrdering.createdAtDesc,
  DateTime? now,
  TxnOccurrence occurrence = TxnOccurrence.occurred,
}) {
  if (!filter.rootGroup.containsSubtagExpansion) {
    final groups = expandTagGroups(filter, const []);
    return buildTransactionQuery(
      db,
      filter,
      tagGroups: groups,
      limit: limit,
      ordering: ordering,
      now: now,
      occurrence: occurrence,
    ).watch();
  }
  final tagsStream = (db.select(
    db.tags,
  )..where((t) => t.archived.equals(false))).watch();
  final tagPayloadStream = tagsStream
      .map((tags) => (tags: tags, groups: expandTagGroups(filter, tags)))
      .distinct((a, b) => _tagGroupsEqual(a.groups, b.groups));
  return _switchMap(tagPayloadStream, (payload) {
    return buildTransactionQuery(
      db,
      filter,
      tagGroups: payload.groups,
      activeTags: payload.tags,
      limit: limit,
      ordering: ordering,
      now: now,
      occurrence: occurrence,
    ).watch();
  });
}

/// Reduces a set of already-filtered transactions to a single Stat value. Pure
/// and synchronous so the sign logic has one home and is unit-testable;
/// [watchFilteredTransactions] feeds it the reactive rows.
StatValue aggregateStat(List<Transaction> rows, StatAggregation aggregation) {
  switch (aggregation) {
    case StatAggregation.count:
      return StatValue(
        aggregation: aggregation,
        amountCents: BigInt.zero,
        count: rows.length,
      );
    case StatAggregation.sum:
      var total = BigInt.zero;
      for (final t in rows) {
        total += t.amount.abs();
      }
      return StatValue(
        aggregation: aggregation,
        amountCents: total,
        count: rows.length,
      );
    case StatAggregation.net:
      var total = BigInt.zero;
      for (final t in rows) {
        switch (t.type) {
          case 'income':
            total += t.amount;
          case 'expense':
            total -= t.amount;
          // Already signed by the balance-adjustment write path.
          case 'balance_adjustment':
            total += t.amount;
          // Transfers move money between the user's own accounts — excluded
          // from net cash flow (mirrors SummaryRepository.byCategory).
          case 'transfer':
            break;
        }
      }
      return StatValue(
        aggregation: aggregation,
        amountCents: total,
        count: rows.length,
      );
  }
}

/// Groups already-filtered transactions into labeled buckets for a Breakdown
/// chart, summing **absolute** amounts (magnitude of activity) per group. Pure
/// and synchronous so the grouping logic has one home and is unit-testable;
/// [SummaryRepository.watchBreakdown] feeds it the reactive rows plus the
/// name/color labels.
///
/// - [BreakdownGroupBy.category] — keyed by `categoryId`, skipping transfers (a
///   transfer has no meaningful spending category — mirrors `byCategory`).
/// - [BreakdownGroupBy.account] — keyed by the source `accountId`.
/// - [BreakdownGroupBy.month] — keyed by the transaction's local `YYYY-MM`.
///
/// [labels] maps a group key → its `(label, colorHex)` and is used only for
/// category/account (month labels are derived from the date). A key missing
/// from [labels] falls back to a generic placeholder. Buckets are returned
/// sorted: month chronologically; category/account by descending magnitude
/// (ties broken by label) so the largest slice leads.
List<BreakdownSlice> aggregateBreakdown(
  List<Transaction> rows,
  BreakdownGroupBy groupBy, {
  Map<String, ({String label, String? colorHex})> labels = const {},
  String missingCategoryLabel = '',
  String missingAccountLabel = '',
  String Function(DateTime date)? monthLabel,
}) {
  final totals = <String, BigInt>{};
  for (final t in rows) {
    String key;
    switch (groupBy) {
      case BreakdownGroupBy.category:
        if (t.type == 'transfer') continue;
        key = t.categoryId;
      case BreakdownGroupBy.account:
        key = t.accountId;
      case BreakdownGroupBy.month:
        final d = DateTime.fromMillisecondsSinceEpoch(t.date.toInt());
        key =
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}';
    }
    totals[key] = (totals[key] ?? BigInt.zero) + t.amount.abs();
  }

  String labelFor(String key) {
    switch (groupBy) {
      case BreakdownGroupBy.category:
        return labels[key]?.label ?? missingCategoryLabel;
      case BreakdownGroupBy.account:
        return labels[key]?.label ?? missingAccountLabel;
      case BreakdownGroupBy.month:
        final parts = key.split('-');
        final year = int.tryParse(parts.first) ?? 0;
        final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        if (month < 1 || month > 12) return key;
        return monthLabel?.call(DateTime(year, month)) ?? key;
    }
  }

  final slices = [
    for (final e in totals.entries)
      BreakdownSlice(
        key: e.key,
        label: labelFor(e.key),
        totalCents: e.value,
        colorHex: labels[e.key]?.colorHex,
      ),
  ];

  switch (groupBy) {
    case BreakdownGroupBy.month:
      slices.sort((a, b) => a.key.compareTo(b.key));
    case BreakdownGroupBy.category:
    case BreakdownGroupBy.account:
      slices.sort((a, b) {
        final byTotal = b.totalCents.compareTo(a.totalCents);
        return byTotal != 0 ? byTotal : a.label.compareTo(b.label);
      });
  }
  return slices;
}

bool _tagGroupsEqual(List<Set<String>> a, List<Set<String>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length || !a[i].containsAll(b[i])) return false;
  }
  return true;
}

/// Minimal switchMap: each outer event cancels the previous inner
/// subscription before subscribing to the new inner stream.
Stream<T> _switchMap<S, T>(
  Stream<S> source,
  Stream<T> Function(S value) mapper,
) {
  late StreamController<T> controller;
  StreamSubscription<S>? outer;
  StreamSubscription<T>? inner;
  controller = StreamController<T>(
    onListen: () {
      outer = source.listen(
        (value) {
          inner?.cancel();
          inner = mapper(
            value,
          ).listen(controller.add, onError: controller.addError);
        },
        onError: controller.addError,
        // Drift watch streams only complete when the database closes; at that
        // point the inner stream is closing too.
        onDone: () => controller.close(),
      );
    },
    onCancel: () async {
      await inner?.cancel();
      await outer?.cancel();
    },
  );
  return controller.stream;
}
