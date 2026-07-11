import 'package:drift/drift.dart';

import '../../database.dart';
import '../ids.dart';
import 'repository_base.dart';

typedef DashboardLayoutEntry = ({
  String id,
  String options,
  int position,
  String width,
});
typedef DashboardLayoutExpectation = ({
  String options,
  String width,
  BigInt updatedAt,
});

/// Reads and writes for the persisted home dashboard layout
/// (docs/home-dashboard.md). Each row is one tile; `options` is an opaque JSON
/// string of display options and `filterId` is a soft reference into
/// `saved_filters` (null for the balance card). This layer never parses
/// `options` — callers serialize/deserialize at the edge.
class DashboardRepository extends RepositoryBase {
  DashboardRepository(super.db);

  /// Active widgets in display order (by `position`, then a stable `createdAt`
  /// tiebreaker). Reactive to local writes and sync merges.
  Stream<List<DashboardWidget>> watchWidgets() =>
      (db.select(db.dashboardWidgets)
            ..where((w) => w.archived.equals(false))
            ..orderBy([
              (w) => OrderingTerm(expression: w.position),
              (w) => OrderingTerm(expression: w.createdAt),
            ]))
          .watch();

  /// One-shot active list, ordered like [watchWidgets].
  Future<List<DashboardWidget>> listActive() =>
      (db.select(db.dashboardWidgets)
            ..where((w) => w.archived.equals(false))
            ..orderBy([
              (w) => OrderingTerm(expression: w.position),
              (w) => OrderingTerm(expression: w.createdAt),
            ]))
          .get();

  /// Exact-id lookup; finds archived widgets too. Null when missing.
  Future<DashboardWidget?> getById(String id) => (db.select(
    db.dashboardWidgets,
  )..where((w) => w.id.equals(id))).getSingleOrNull();

  /// Creates a widget and returns its new id. Pass [id] to use a deterministic
  /// id (the default seed does this so concurrent device seeds converge).
  Future<String> create({
    required String type,
    required int position,
    required String width,
    required String options,
    String? filterId,
    String? id,
  }) async {
    final widgetId = id ?? newUuid();
    final now = currentMs;
    await db
        .into(db.dashboardWidgets)
        .insert(
          DashboardWidgetsCompanion.insert(
            id: widgetId,
            type: type,
            filterId: Value(filterId),
            position: position,
            width: width,
            options: options,
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return widgetId;
  }

  /// Partial update via `Value<T>` (absent = keep, `Value(null)` clears the
  /// nullable `filterId`). Always bumps `updatedAt` and re-dirties.
  Future<void> update(
    String id, {
    Value<String> type = const Value.absent(),
    Value<String?> filterId = const Value.absent(),
    Value<int> position = const Value.absent(),
    Value<String> width = const Value.absent(),
    Value<String> options = const Value.absent(),
  }) async {
    await (db.update(db.dashboardWidgets)..where((w) => w.id.equals(id))).write(
      DashboardWidgetsCompanion(
        type: type,
        filterId: filterId,
        position: position,
        width: width,
        options: options,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
  }

  /// Persists a new display order: writes `position = index` for each id, all
  /// in one transaction, each bumping `updatedAt` + re-dirtying.
  Future<void> reorder(List<String> idsInOrder) async {
    final now = currentMs;
    await db.transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await (db.update(
          db.dashboardWidgets,
        )..where((w) => w.id.equals(idsInOrder[i]))).write(
          DashboardWidgetsCompanion(
            position: Value(i),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
      }
    });
  }

  /// Persists a manual-grid layout snapshot in one transaction: each entry
  /// carries the widget's already-encoded `options` (which embeds its
  /// `{row, col}`), its row-major `position`, and its `width`. Every row bumps
  /// `updatedAt` + re-dirties. Writing every visible widget on each move keeps
  /// `position` consistent and migrates legacy (coord-less) rows on first edit.
  Future<void> applyLayout(List<DashboardLayoutEntry> entries) async {
    final now = currentMs;
    await db.transaction(() async {
      await _writeLayoutEntries(entries, now);
    });
  }

  /// Applies a repair snapshot only if the active dashboard still exactly
  /// matches what the caller validated. Sync may merge a fresher snapshot while
  /// a post-frame repair is waiting; in that case this compare-and-write safely
  /// no-ops instead of overwriting it.
  Future<bool> applyLayoutIfUnchanged(
    List<DashboardLayoutEntry> entries,
    Map<String, DashboardLayoutExpectation> expected,
  ) async {
    final now = currentMs;
    return db.transaction(() async {
      final current = await (db.select(
        db.dashboardWidgets,
      )..where((w) => w.archived.equals(false))).get();
      if (current.length != expected.length ||
          entries.length != expected.length) {
        return false;
      }
      for (final row in current) {
        final snapshot = expected[row.id];
        if (snapshot == null ||
            snapshot.options != row.options ||
            snapshot.width != row.width ||
            snapshot.updatedAt != row.updatedAt) {
          return false;
        }
      }
      if (entries.any((entry) => !expected.containsKey(entry.id))) return false;

      await _writeLayoutEntries(entries, now);
      return true;
    });
  }

  Future<void> _writeLayoutEntries(
    List<DashboardLayoutEntry> entries,
    BigInt now,
  ) async {
    for (final entry in entries) {
      await (db.update(
        db.dashboardWidgets,
      )..where((w) => w.id.equals(entry.id))).write(
        DashboardWidgetsCompanion(
          options: Value(entry.options),
          position: Value(entry.position),
          width: Value(entry.width),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
    }
  }

  /// Soft delete: `archived = true` + tombstone, atomically.
  Future<void> archive(String id) async {
    final now = currentMs;
    await db.transaction(() async {
      await (db.update(
        db.dashboardWidgets,
      )..where((w) => w.id.equals(id))).write(
        DashboardWidgetsCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('dashboardWidgets', id);
    });
  }

  /// Auto-seeds the default dashboard at most once per device. Runs [writeSeed]
  /// (which should create the default saved filters + widgets, ideally with
  /// deterministic ids) only when no widgets exist yet and the device hasn't
  /// seeded before; either way the one-time guard is then set so a default the
  /// user later deletes is never resurrected.
  ///
  /// [respectDeleteHistory] is used for remote accounts after their initial
  /// pull. A dashboard-widget tombstone means the empty dashboard may be an
  /// intentional user choice, so defaults must not be recreated on this device.
  Future<void> seedDefaultIfEmpty(
    Future<void> Function() writeSeed, {
    bool respectDeleteHistory = false,
  }) async {
    await db.transaction(() async {
      final state = await (db.select(
        db.syncState,
      )..where((s) => s.id.equals('singleton'))).getSingleOrNull();
      if (state?.dashboardSeeded ?? false) return;

      final existing = await (db.select(db.dashboardWidgets)..limit(1)).get();
      var wasDeleted = false;
      if (respectDeleteHistory && existing.isEmpty) {
        final tombstones =
            await (db.select(db.tombstones)
                  ..where((t) => t.entityTable.equals('dashboardWidgets'))
                  ..limit(1))
                .get();
        wasDeleted = tombstones.isNotEmpty;
      }
      if (existing.isEmpty && !wasDeleted) {
        await writeSeed();
      }

      // Mark attempted regardless, so deleted defaults cannot be resurrected
      // later on this device.
      await db
          .into(db.syncState)
          .insert(
            SyncStateCompanion.insert(
              id: const Value('singleton'),
              dashboardSeeded: const Value(true),
            ),
            onConflict: DoUpdate(
              (_) => const SyncStateCompanion(dashboardSeeded: Value(true)),
            ),
          );
    });
  }
}
