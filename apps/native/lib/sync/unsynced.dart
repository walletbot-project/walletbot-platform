import 'package:app/database.dart';
import 'package:drift/drift.dart';

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
  final tables = <TableInfo<Table, dynamic>>[
    db.accounts,
    db.categories,
    db.transactions,
    db.tags,
    db.transactionTags,
    db.savedFilters,
    db.dashboardWidgets,
    db.tombstones,
  ];
  // One compound select with a single trailing LIMIT: SQLite stops at the
  // first dirty row it finds, and each branch is served by that table's
  // partial `*_needs_sync` index.
  final probe = tables
      .map((table) => 'SELECT 1 FROM ${table.actualTableName} WHERE dirty = 1')
      .join(' UNION ALL ');
  final row = await db.customSelect('$probe LIMIT 1').getSingleOrNull();
  return row != null;
}
