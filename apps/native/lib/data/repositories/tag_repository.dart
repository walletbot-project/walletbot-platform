import 'package:drift/drift.dart';

import '../../database.dart';
import '../ids.dart';
import '../models/entity_counts.dart';
import 'repository_base.dart';

/// What happens to descendants when a tag is archived.
enum TagArchiveMode {
  /// Direct, non-archived children are re-parented to the deleted tag's
  /// parent (becoming top-level when there is none).
  reparentChildren,

  /// Every descendant is archived + tombstoned along with the tag.
  cascade,
}

/// Reads and writes for hierarchical tags (`parentId` links), including the
/// tree-aware domain logic: reparent backfill and the two archive modes.
class TagRepository extends RepositoryBase {
  TagRepository(super.db);

  /// Active tags, unsorted (sort or build the tree at the call site).
  Stream<List<Tag>> watchActive() =>
      (db.select(db.tags)..where((t) => t.archived.equals(false))).watch();

  /// One-shot list, active-only by default.
  Future<List<Tag>> listAll({bool includeArchived = false}) {
    final query = db.select(db.tags);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    return query.get();
  }

  /// Alias of [listAll] with the default scope, for readable call sites.
  Future<List<Tag>> listActive() => listAll();

  /// Exact-id lookup; finds archived tags too. Null when missing.
  Future<Tag?> getById(String id) =>
      (db.select(db.tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Active tags with their transaction counts, name-ordered. Keep
  /// `readsFrom` in lockstep with the SQL — it is what keeps counts live.
  Stream<List<TagWithCount>> watchWithCounts() {
    final query = db.customSelect(
      '''
        SELECT tg.id, tg.name, tg.description, tg.parent_id, tg.color,
               tg.is_archived, tg.created_at, tg.updated_at, tg.dirty,
               COUNT(tt.id) AS transaction_count
        FROM tags tg
        LEFT JOIN transaction_tags tt ON tt.tag_id = tg.id
        WHERE tg.is_archived = 0
        GROUP BY tg.id, tg.name, tg.description, tg.parent_id, tg.color,
                 tg.is_archived, tg.created_at, tg.updated_at, tg.dirty
        ORDER BY tg.name COLLATE NOCASE
      ''',
      readsFrom: {db.tags, db.transactionTags},
    );

    return query.watch().map((rows) {
      return rows.map((row) {
        return TagWithCount(
          tag: Tag(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            description: row.readNullable<String>('description'),
            parentId: row.readNullable<String>('parent_id'),
            color: row.read<String>('color'),
            archived: row.read<bool>('is_archived'),
            createdAt: row.read<BigInt>('created_at'),
            updatedAt: row.read<BigInt>('updated_at'),
            dirty: row.read<bool>('dirty'),
          ),
          transactionCount: row.read<int>('transaction_count'),
        );
      }).toList();
    });
  }

  /// Live total spent (expenses only) on transactions carrying [tagId] within
  /// `[fromMs, toExclusiveMs)`, grouped by transaction currency. Computed with
  /// a SQL `SUM` aggregate over the tag join (not by loading rows), and
  /// re-emits when transactions or joins change. Only the exact tag is counted
  /// (descendants are not rolled up).
  Stream<Map<String, BigInt>> watchSpendByCurrency(
    String tagId, {
    required BigInt fromMs,
    required BigInt toExclusiveMs,
  }) {
    final currency = db.transactions.currency;
    final total = db.transactions.amount.sum();
    final query =
        db.selectOnly(db.transactions).join([
            innerJoin(
              db.transactionTags,
              db.transactionTags.transactionId.equalsExp(db.transactions.id),
            ),
          ])
          ..addColumns([currency, total])
          ..where(
            db.transactionTags.tagId.equals(tagId) &
                db.transactions.archived.equals(false) &
                db.transactions.type.equals('expense') &
                db.transactions.date.isBiggerOrEqualValue(fromMs) &
                db.transactions.date.isSmallerThanValue(toExclusiveMs),
          )
          ..groupBy([currency]);

    return query.watch().map((rows) {
      final result = <String, BigInt>{};
      for (final row in rows) {
        final cur = row.read(currency);
        final sum = row.read(total);
        if (cur != null && sum != null) result[cur] = sum;
      }
      return result;
    });
  }

  /// IDs of every active descendant of [tagId] (children, grandchildren, …).
  Future<Set<String>> descendantIds(String tagId) async {
    final all = await listActive();
    return descendantIdsOf(all, tagId);
  }

  /// Creates a tag (optionally nested under [parentId]) and returns its id.
  Future<String> create({
    required String name,
    String? description,
    String? parentId,
    String? color,
  }) async {
    final id = newUuid();
    final now = currentMs;
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
            parentId: Value(parentId),
            color: Value.absentIfNull(color),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return id;
  }

  /// Updates a tag. When [parentId] is present with a non-null value that
  /// differs from the current parent, every transaction tagged with this tag
  /// (or any of its descendants) also gets joins for every ancestor in the
  /// new chain — same transaction, so the move is atomic. Moving a tag to
  /// top-level (`Value(null)`) intentionally does NOT remove existing
  /// ancestor joins (the backfill is asymmetric by design).
  Future<void> update(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String> color = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
  }) async {
    final now = currentMs;
    final current = await getById(id);
    if (current == null) {
      throw ArgumentError.value(id, 'id', 'Tag not found');
    }
    final previousParentId = current.parentId;

    await db.transaction(() async {
      await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          name: name,
          description: description,
          color: color,
          parentId: parentId,
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );

      final newParentId = parentId.present ? parentId.value : null;
      if (newParentId != null && newParentId != previousParentId) {
        final allActive = await listActive();
        final ancestors = ancestorChainOf(allActive, newParentId);
        final descendants = descendantIdsOf(allActive, id);
        final affectedTagIds = <String>{id, ...descendants};

        final transactionIds = <String>{};
        for (final tagId in affectedTagIds) {
          final joins = await (db.select(
            db.transactionTags,
          )..where((tt) => tt.tagId.equals(tagId))).get();
          for (final j in joins) {
            transactionIds.add(j.transactionId);
          }
        }

        for (final txId in transactionIds) {
          for (final ancestor in ancestors) {
            final existing =
                await (db.select(db.transactionTags)
                      ..where((tt) => tt.transactionId.equals(txId))
                      ..where((tt) => tt.tagId.equals(ancestor.id)))
                    .getSingleOrNull();
            if (existing != null) continue;
            await db
                .into(db.transactionTags)
                .insert(
                  TransactionTagsCompanion.insert(
                    id: '${txId}__${ancestor.id}',
                    transactionId: txId,
                    tagId: ancestor.id,
                    createdAt: now,
                    updatedAt: now,
                    dirty: const Value(true),
                  ),
                );
          }
        }
      }
    });
  }

  /// Archives a tag (+ tombstone), handling descendants per [mode], all in
  /// one transaction.
  Future<void> archive(String id, {required TagArchiveMode mode}) async {
    final now = currentMs;
    await db.transaction(() async {
      if (mode == TagArchiveMode.cascade) {
        final allActive = await listActive();
        final descendants = descendantIdsOf(allActive, id);
        for (final descendantId in descendants) {
          await (db.update(
            db.tags,
          )..where((t) => t.id.equals(descendantId))).write(
            TagsCompanion(
              archived: const Value(true),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
          await markDeleted('tags', descendantId);
        }
      } else {
        final deletedTag = await getById(id);
        final grandparentId = deletedTag?.parentId;

        final directChildren =
            await (db.select(db.tags)
                  ..where((t) => t.parentId.equals(id))
                  ..where((t) => t.archived.equals(false)))
                .get();
        for (final child in directChildren) {
          await (db.update(db.tags)..where((t) => t.id.equals(child.id))).write(
            TagsCompanion(
              parentId: Value(grandparentId),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
        }
      }

      await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('tags', id);
    });
  }
}

/// Walks `parentId` links upward from [startParentId] through [all],
/// cycle-safe. Returns the chain nearest-first.
List<Tag> ancestorChainOf(List<Tag> all, String? startParentId) {
  final byId = {for (final t in all) t.id: t};
  final chain = <Tag>[];
  final seen = <String>{};
  var cursor = startParentId;
  while (cursor != null) {
    if (seen.contains(cursor)) break;
    seen.add(cursor);
    final next = byId[cursor];
    if (next == null) break;
    chain.add(next);
    cursor = next.parentId;
  }
  return chain;
}

/// BFS over `parentId` links downward from [rootId] through [all].
Set<String> descendantIdsOf(List<Tag> all, String rootId) {
  final result = <String>{};
  final queue = <String>[rootId];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    for (final t in all) {
      if (t.parentId == id && !result.contains(t.id)) {
        result.add(t.id);
        queue.add(t.id);
      }
    }
  }
  return result;
}
