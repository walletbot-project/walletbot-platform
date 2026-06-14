import 'package:drift/drift.dart';

import '../database.dart';
import '../shared/dates.dart';

/// Upserts a tombstone for `(entityTable, entityId)` with `dirty = true` so
/// the next push round propagates the deletion. Safe to call multiple times
/// for the same entity — later calls bump `deletedAt` / `updatedAt`.
///
/// This is an *app-write* primitive (the delete half of the
/// archive + tombstone pair every local delete must produce). The sync engine
/// only reads dirty tombstones; it never calls this.
Future<void> writeTombstone(
  AppDatabase db,
  String entityTable,
  String entityId,
) async {
  final now = nowMs();
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
