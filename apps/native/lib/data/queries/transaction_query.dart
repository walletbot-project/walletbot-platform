import 'package:drift/drift.dart';

import '../../database.dart';
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
    return [for (final id in filter.tagIds) {id}];
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
  final effectiveGroups = filter.tagMatch == TagMatch.any && tagGroups.isNotEmpty
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
