import 'package:drift/drift.dart';

import '../database.dart';

/// Upserts a tombstone for `(entityTable, entityId)` with `dirty = true` so
/// the next push round propagates the deletion. Safe to call multiple times
/// for the same entity — later calls bump `deletedAt` / `updatedAt`.
///
/// Companion to the inline pattern in `tool_executors._writeTombstone`;
/// kept as a top-level function so UI write paths (categories_view,
/// tags_view) can share the exact same semantics.
Future<void> writeTombstone(
  AppDatabase db,
  String entityTable,
  String entityId,
) async {
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  final existing = await (db.select(db.tombstones)
        ..where(
          (t) =>
              t.entityTable.equals(entityTable) & t.entityId.equals(entityId),
        ))
      .getSingleOrNull();
  if (existing != null) {
    await (db.update(db.tombstones)
          ..where(
            (t) =>
                t.entityTable.equals(entityTable) &
                t.entityId.equals(entityId),
          ))
        .write(
          TombstonesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
  } else {
    await db
        .into(db.tombstones)
        .insert(
          TombstonesCompanion.insert(
            entityTable: entityTable,
            entityId: entityId,
            deletedAt: now,
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
  }
}
