import 'package:drift/drift.dart';

import '../../database.dart';
import '../ids.dart';
import 'repository_base.dart';

/// Reads and writes for saved filters (the "Saved View" primitive from
/// docs/home-dashboard.md). `config` is the opaque JSON string of the canonical
/// condition tree (`TransactionFilter.toCanonicalJson`); this layer never
/// parses it — callers serialize/deserialize at the edge.
class SavedFilterRepository extends RepositoryBase {
  SavedFilterRepository(super.db);

  /// Active saved filters, name-ordered.
  Stream<List<SavedFilter>> watchActive() =>
      (db.select(db.savedFilters)
            ..where((f) => f.archived.equals(false))
            ..orderBy([(f) => OrderingTerm(expression: f.name)]))
          .watch();

  /// One-shot list, active-only by default.
  Future<List<SavedFilter>> listActive() => (db.select(
    db.savedFilters,
  )..where((f) => f.archived.equals(false))).get();

  /// Exact-id lookup; finds archived filters too. Null when missing.
  Future<SavedFilter?> getById(String id) => (db.select(
    db.savedFilters,
  )..where((f) => f.id.equals(id))).getSingleOrNull();

  /// Creates a saved filter and returns its new id. Pass [id] to use a
  /// deterministic id (the default seed does this so concurrent device seeds
  /// converge under LWW).
  Future<String> create({
    required String name,
    required String config,
    String? id,
  }) async {
    final filterId = id ?? newUuid();
    final now = currentMs;
    await db
        .into(db.savedFilters)
        .insert(
          SavedFiltersCompanion.insert(
            id: filterId,
            name: name,
            config: config,
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return filterId;
  }

  /// Partial update via `Value<T>` (absent = keep). Always bumps `updatedAt`
  /// and re-dirties.
  Future<void> update(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String> config = const Value.absent(),
  }) async {
    await (db.update(db.savedFilters)..where((f) => f.id.equals(id))).write(
      SavedFiltersCompanion(
        name: name,
        config: config,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
  }

  /// Soft delete: `archived = true` + tombstone, atomically.
  Future<void> archive(String id) async {
    final now = currentMs;
    await db.transaction(() async {
      await (db.update(db.savedFilters)..where((f) => f.id.equals(id))).write(
        SavedFiltersCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('savedFilters', id);
    });
  }
}
