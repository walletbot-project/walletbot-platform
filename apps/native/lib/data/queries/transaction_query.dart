import 'dart:async';

import 'package:drift/drift.dart';

import '../../database.dart';
import '../models/summaries.dart';
import '../models/transaction_filter.dart';

/// Result ordering for transaction lists. The activity screen orders strictly
/// by creation time (newest first) so day headers stay contiguous; the agent
/// orders by the (possibly estimated) transaction date.
enum TxnOrdering { createdAtDesc, dateDesc }

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
  int? limit,
  TxnOrdering ordering = TxnOrdering.createdAtDesc,
  DateTime? now,
  BigInt? exactFromMs,
  BigInt? exactToInclusiveMs,
}) {
  final query = db.select(db.transactions)
    ..where((t) => t.archived.equals(false));

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
    query.where((t) => t.name.lower().like(pattern));
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

  switch (ordering) {
    case TxnOrdering.createdAtDesc:
      query.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    case TxnOrdering.dateDesc:
      query.orderBy([(t) => OrderingTerm.desc(t.date)]);
  }
  if (limit != null) {
    query.limit(limit);
  }
  return query;
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
}) {
  if (filter.tagIds.isEmpty || !filter.includeSubtags) {
    final groups = expandTagGroups(filter, const []);
    return buildTransactionQuery(
      db,
      filter,
      tagGroups: groups,
      limit: limit,
      ordering: ordering,
      now: now,
    ).watch();
  }
  final tagsStream = (db.select(
    db.tags,
  )..where((t) => t.archived.equals(false))).watch();
  final groupsStream = tagsStream
      .map((tags) => expandTagGroups(filter, tags))
      .distinct(_tagGroupsEqual);
  return _switchMap(groupsStream, (groups) {
    return buildTransactionQuery(
      db,
      filter,
      tagGroups: groups,
      limit: limit,
      ordering: ordering,
      now: now,
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

/// Spanish three-letter month abbreviations for [BreakdownGroupBy.month]
/// labels, indexed by month-1. Kept local so the breakdown needs no
/// `intl`/locale dependency.
const _esMonthsShort = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

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
        return labels[key]?.label ?? '(sin categoría)';
      case BreakdownGroupBy.account:
        return labels[key]?.label ?? '(sin cuenta)';
      case BreakdownGroupBy.month:
        final parts = key.split('-');
        final year = int.tryParse(parts.first) ?? 0;
        final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        if (month < 1 || month > 12) return key;
        return '${_esMonthsShort[month - 1]} $year';
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
