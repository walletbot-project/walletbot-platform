import 'package:app/database.dart';
import 'package:drift/drift.dart';

List<TableInfo<Table, dynamic>> _syncedTables(AppDatabase db) => [
  db.accounts,
  db.categories,
  db.transactions,
  db.tags,
  db.transactionTags,
  db.savedFilters,
  db.dashboardWidgets,
  db.agentMemories,
  db.recurrences,
  db.tombstones,
];

/// Flags every row that takes part in the push as unsynced, so the first sync
/// of a freshly promoted local account sends all of its history.
///
/// A local account never pushes, and `dirty` defaults to false, so nothing
/// guarantees every one of its rows is flagged: any insert that did not set it
/// would never be sent. Setting the flag is idempotent.
Future<void> markAllSyncedTablesDirty(AppDatabase db) async {
  await db.transaction(() async {
    for (final table in _syncedTables(db)) {
      await db.customStatement(
        'UPDATE ${table.actualTableName} SET dirty = 1 WHERE dirty = 0',
      );
    }
  });
}

/// Whether [db] holds local writes the sync engine has not pushed yet.
///
/// The table list mirrors `SyncEngine._collectChunk`: every table carrying a
/// `dirty` flag that takes part in the push. The voice tables are deliberately
/// absent — they replicate through `VoiceSessionRemoteSync`, not the entity
/// sync.
///
/// Asked before signing out of a remote account, because dropping the local
/// database takes those writes with it. [SyncStatus] cannot answer this:
/// an account that simply never synced this launch — a cold offline start —
/// sits at `SyncStatus.idle` with nothing pending at all, and warning there
/// would be crying wolf.
Future<bool> hasUnsyncedChanges(AppDatabase db) async {
  final tables = _syncedTables(db);
  // One compound select with a single trailing LIMIT: SQLite stops at the
  // first dirty row it finds, and each branch is served by that table's
  // partial `*_needs_sync` index.
  final probe = tables
      .map((table) => 'SELECT 1 FROM ${table.actualTableName} WHERE dirty = 1')
      .join(' UNION ALL ');
  final row = await db.customSelect('$probe LIMIT 1').getSingleOrNull();
  return row != null;
}
