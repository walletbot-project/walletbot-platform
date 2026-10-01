import 'package:drift/drift.dart';

import '../database.dart';

/// Applies a single page of `pull` output to the local Drift database in one
/// transaction. Implements the LWW conflict-resolution rules from
/// `docs/data-model.md` § "Merge local".
///
/// `currentCounter` is the server's counter at the time of this page; the
/// caller is responsible for committing `sync_state.last_server_seq =
/// currentCounter` only AFTER the final (`hasMore = false`) page has been
/// applied.
class PullPageMerger {
  PullPageMerger(this.db);
  final AppDatabase db;

  Future<void> applyPage({
    required List<Map<String, Object?>> rows,
    required List<Map<String, Object?>> tombstones,
  }) async {
    if (rows.isEmpty && tombstones.isEmpty) return;
    await db.transaction(() async {
      for (final r in rows) {
        final tableName = r['tableName'] as String;
        final raw = r['row'] as Map<String, Object?>;
        await _applyRemoteRow(tableName, raw);
      }
      for (final t in tombstones) {
        final tableName = t['tableName'] as String;
        final entityId = t['entityId'] as String;
        final deletedAt = _asBigInt(t['deletedAt']);
        await _applyRemoteTombstone(tableName, entityId, deletedAt);
      }
    });
  }

  // ─── Per-table row apply ─────────────────────────────────────────────────

  Future<void> _applyRemoteRow(String tableName, Map<String, Object?> r) async {
    final id = r['id'] as String;
    final remoteUpdatedAt = _asBigInt(r['updatedAt']);

    // Local-tombstone-vs-remote-row: spec §"Si existe tombstone local para X".
    final tomb =
        await (db.select(db.tombstones)..where(
              (t) => t.entityTable.equals(tableName) & t.entityId.equals(id),
            ))
            .getSingleOrNull();
    if (tomb != null) {
      final archivedSeriesTemplate =
          !tomb.dirty && tableName == 'transactions' && _isArchivedSeriesRow(r);
      if (!archivedSeriesTemplate && tomb.deletedAt >= remoteUpdatedAt) {
        // Local delete is newer; keep tombstone (it'll push and revoke).
        return;
      }
      // Remote row is newer than local delete — drop tombstone and accept.
      await (db.delete(db.tombstones)..where(
            (t) => t.entityTable.equals(tableName) & t.entityId.equals(id),
          ))
          .go();
    }

    switch (tableName) {
      case 'accounts':
        await _applyAccount(id, remoteUpdatedAt, r);
        break;
      case 'categories':
        await _applyCategory(id, remoteUpdatedAt, r);
        break;
      case 'tags':
        await _applyTag(id, remoteUpdatedAt, r);
        break;
      case 'transactions':
        await _applyTransaction(id, remoteUpdatedAt, r);
        break;
      case 'transactionTags':
        await _applyTransactionTag(id, remoteUpdatedAt, r);
        break;
      case 'savedFilters':
        await _applySavedFilter(id, remoteUpdatedAt, r);
        break;
      case 'dashboardWidgets':
        await _applyDashboardWidget(id, remoteUpdatedAt, r);
        break;
      case 'agentMemories':
        await _applyAgentMemory(id, remoteUpdatedAt, r);
        break;
      case 'recurrences':
        await _applyRecurrence(id, remoteUpdatedAt, r);
        break;
      default:
        // Unknown table — skip rather than crash. Forward-compat: a future
        // server may sync more tables than this client knows.
        break;
    }
  }

  bool _isArchivedSeriesRow(Map<String, Object?> row) =>
      row['isArchived'] == true && row['recurrenceId'] is String;

  Future<void> _applyAccount(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = AccountsCompanion(
      id: Value(id),
      name: Value(r['name'] as String),
      currency: Value(r['currency'] as String),
      description: Value(r['description'] as String?),
      color: Value((r['color'] as String?) ?? kDefaultAccountColor),
      icon: Value((r['icon'] as String?) ?? kDefaultAccountIcon),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.accounts).insertOnConflictUpdate(companion);
  }

  Future<void> _applyCategory(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = CategoriesCompanion(
      id: Value(id),
      name: Value(r['name'] as String),
      description: Value(r['description'] as String?),
      color: Value((r['color'] as String?) ?? kDefaultCategoryColor),
      icon: Value((r['icon'] as String?) ?? kDefaultCategoryIcon),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.categories).insertOnConflictUpdate(companion);
  }

  Future<void> _applyTag(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.tags,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = TagsCompanion(
      id: Value(id),
      name: Value(r['name'] as String),
      description: Value(r['description'] as String?),
      parentId: Value(r['parentId'] as String?),
      color: Value((r['color'] as String?) ?? kDefaultTagColor),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.tags).insertOnConflictUpdate(companion);
  }

  Future<void> _applyTransaction(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) {
        // An upgrading v4 client may have an offline edit but no columns for
        // the series it belongs to. Keep that edit while hydrating metadata
        // which the old binary could not have changed.
        if (existing.recurrenceId == null && r['recurrenceId'] is String) {
          await (db.update(
            db.transactions,
          )..where((t) => t.id.equals(id))).write(
            TransactionsCompanion(
              recurrenceId: Value(r['recurrenceId'] as String),
              recurrenceIndex: Value(_asIntOrNull(r['recurrenceIndex'])),
            ),
          );
        }
        return;
      }
    }
    final companion = TransactionsCompanion(
      id: Value(id),
      type: Value(r['type'] as String),
      name: Value(r['name'] as String),
      description: Value(r['description'] as String?),
      status: Value(r['status'] as String),
      date: Value(_asBigInt(r['date'])),
      dateConfirmed: Value(r['dateConfirmed'] as bool? ?? true),
      timeStatus: Value(_transactionTimeStatus(r['timeStatus'])),
      accountId: Value(r['accountId'] as String),
      categoryId: Value(r['categoryId'] as String),
      amount: Value(_asBigInt(r['amount'])),
      currency: Value(r['currency'] as String),
      toAccountId: Value(r['toAccountId'] as String?),
      toAmount: Value(_asBigIntOrNull(r['toAmount'])),
      toCurrency: Value(r['toCurrency'] as String?),
      exchangeRate: Value((r['exchangeRate'] as num?)?.toDouble()),
      balanceAfter: Value(_asBigIntOrNull(r['balanceAfter'])),
      recurrenceId: Value(r['recurrenceId'] as String?),
      recurrenceIndex: Value(_asIntOrNull(r['recurrenceIndex'])),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.transactions).insertOnConflictUpdate(companion);
  }

  Future<void> _applyTransactionTag(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.transactionTags,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = TransactionTagsCompanion(
      id: Value(id),
      transactionId: Value(r['transactionId'] as String),
      tagId: Value(r['tagId'] as String),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.transactionTags).insertOnConflictUpdate(companion);
  }

  Future<void> _applySavedFilter(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.savedFilters,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = SavedFiltersCompanion(
      id: Value(id),
      name: Value(r['name'] as String),
      config: Value(r['config'] as String),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.savedFilters).insertOnConflictUpdate(companion);
  }

  Future<void> _applyDashboardWidget(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.dashboardWidgets,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = DashboardWidgetsCompanion(
      id: Value(id),
      type: Value(r['type'] as String),
      filterId: Value(r['filterId'] as String?),
      position: Value((r['position'] as num).toInt()),
      width: Value(r['width'] as String),
      options: Value(r['options'] as String),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.dashboardWidgets).insertOnConflictUpdate(companion);
  }

  Future<void> _applyAgentMemory(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.agentMemories,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = AgentMemoriesCompanion(
      id: Value(id),
      content: Value(r['content'] as String),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.agentMemories).insertOnConflictUpdate(companion);
  }

  Future<void> _applyRecurrence(
    String id,
    BigInt remoteUpdatedAt,
    Map<String, Object?> r,
  ) async {
    final existing = await (db.select(
      db.recurrences,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.dirty) {
      if (existing.updatedAt >= remoteUpdatedAt) return;
    }
    final companion = RecurrencesCompanion(
      id: Value(id),
      frequency: Value(r['frequency'] as String),
      dayInterval: Value(_asIntOrNull(r['dayInterval'])),
      anchorDate: Value(_asBigInt(r['anchorDate'])),
      endDate: Value(_asBigIntOrNull(r['endDate'])),
      archived: Value(r['isArchived'] as bool? ?? false),
      createdAt: Value(_asBigInt(r['createdAt'])),
      updatedAt: Value(remoteUpdatedAt),
      dirty: const Value(false),
    );
    await db.into(db.recurrences).insertOnConflictUpdate(companion);
  }

  // ─── Tombstone apply ─────────────────────────────────────────────────────

  Future<void> _applyRemoteTombstone(
    String tableName,
    String entityId,
    BigInt deletedAt,
  ) async {
    // Spec §"Para cada tombstone remoto sobre entidad X". If the local row
    // is alive and newer than the remote delete, defend the local row.
    bool keepLocalRow = false;
    switch (tableName) {
      case 'accounts':
        final row = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.accounts,
            )..where((a) => a.id.equals(entityId))).go();
          }
        }
        break;
      case 'categories':
        final row = await (db.select(
          db.categories,
        )..where((c) => c.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.categories,
            )..where((c) => c.id.equals(entityId))).go();
          }
        }
        break;
      case 'tags':
        final row = await (db.select(
          db.tags,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.tags,
            )..where((t) => t.id.equals(entityId))).go();
          }
        }
        break;
      case 'transactions':
        final row = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.transactions,
            )..where((t) => t.id.equals(entityId))).go();
            // Cascade local joins. Their tombstones are emitted on the next
            // write path; the local DB stays consistent regardless.
            await (db.delete(
              db.transactionTags,
            )..where((j) => j.transactionId.equals(entityId))).go();
          }
        }
        break;
      case 'transactionTags':
        final row = await (db.select(
          db.transactionTags,
        )..where((j) => j.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.transactionTags,
            )..where((j) => j.id.equals(entityId))).go();
          }
        }
        break;
      case 'savedFilters':
        final row = await (db.select(
          db.savedFilters,
        )..where((f) => f.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.savedFilters,
            )..where((f) => f.id.equals(entityId))).go();
          }
        }
        break;
      case 'dashboardWidgets':
        final row = await (db.select(
          db.dashboardWidgets,
        )..where((w) => w.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.dashboardWidgets,
            )..where((w) => w.id.equals(entityId))).go();
          }
        }
        break;
      case 'agentMemories':
        final row = await (db.select(
          db.agentMemories,
        )..where((m) => m.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.agentMemories,
            )..where((m) => m.id.equals(entityId))).go();
          }
        }
        break;
      case 'recurrences':
        final row = await (db.select(
          db.recurrences,
        )..where((x) => x.id.equals(entityId))).getSingleOrNull();
        if (row != null) {
          if (row.dirty && row.updatedAt > deletedAt) {
            keepLocalRow = true;
          } else {
            await (db.delete(
              db.recurrences,
            )..where((x) => x.id.equals(entityId))).go();
          }
        }
        break;
    }

    if (keepLocalRow) {
      // Local wins; don't write the remote tombstone — the next push will
      // upsert the row again on the server. The remote tombstone's seq is
      // still implicitly applied via last_server_seq advance.
      return;
    }

    // Upsert local tombstone with dirty = false. If a local tombstone
    // already exists with a later deletedAt, defend it (it'll push later).
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final existing =
        await (db.select(db.tombstones)..where(
              (t) =>
                  t.entityTable.equals(tableName) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.dirty && existing.deletedAt > deletedAt) {
        return;
      }
      await (db.update(db.tombstones)..where(
            (t) =>
                t.entityTable.equals(tableName) & t.entityId.equals(entityId),
          ))
          .write(
            TombstonesCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(now),
              dirty: const Value(false),
            ),
          );
    } else {
      await db
          .into(db.tombstones)
          .insert(
            TombstonesCompanion.insert(
              entityTable: tableName,
              entityId: entityId,
              deletedAt: deletedAt,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(false),
            ),
          );
    }
  }
}

TransactionTimeStatus _transactionTimeStatus(Object? raw) {
  if (raw is String) {
    for (final status in TransactionTimeStatus.values) {
      if (status.name == raw) return status;
    }
  }
  return TransactionTimeStatus.none;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

BigInt _asBigInt(Object? v) {
  if (v is BigInt) return v;
  if (v is int) return BigInt.from(v);
  if (v is double) return BigInt.from(v.toInt());
  if (v is String) return BigInt.parse(v);
  throw FormatException('expected int-like, got: $v');
}

BigInt? _asBigIntOrNull(Object? v) => v == null ? null : _asBigInt(v);

/// The wire carries these as int64; the columns are plain ints (an occurrence
/// index and a day interval are both small by construction).
int? _asIntOrNull(Object? v) => v == null ? null : _asBigInt(v).toInt();
