import '../../database.dart';
import '../../shared/dates.dart';
import '../tombstones.dart';

/// Base for all repositories. Repositories are the ONLY app-level write path:
///
///  - every local insert/update sets `dirty = true` and bumps `updatedAt` in
///    the same statement (the sync push-ack and LWW merge depend on it);
///  - every delete is `archived = true` + tombstone, both inside one
///    `db.transaction()` (never a hard row delete, except transactionTags
///    joins which are hard-deleted + tombstoned);
///  - `dirty = false` is never written here — only the sync engine clears it.
///
/// The sync engine's merge/recompute writes stay in `lib/sync/` with their own
/// deliberately different semantics (merge writes `dirty = false`); routing
/// them through repositories would echo every pulled row back to the server.
///
/// Repositories are stateless pass-throughs over the per-user [AppDatabase]
/// (no caches, no broadcast controllers) so account switching only has to
/// swap the database instance.
abstract class RepositoryBase {
  RepositoryBase(this.db);

  final AppDatabase db;

  BigInt get currentMs => nowMs();

  /// The delete half of the archive + tombstone pair.
  Future<void> markDeleted(String entityTable, String entityId) =>
      writeTombstone(db, entityTable, entityId);
}
