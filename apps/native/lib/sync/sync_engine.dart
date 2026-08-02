import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../app_config/client_info.dart';
import '../database.dart';
import 'sync_merge.dart';
import 'sync_recompute.dart';
import 'sync_status.dart';
import 'wire.dart';

/// The `error` value returned by `sync/*:pull` and `push` when the backend
/// rejects this client for being below the platform's `minSupportedVersion`.
/// Mirrors `packages/backend/convex/config/helpers.ts` `CLIENT_OUTDATED`.
const _clientOutdatedError = 'client_outdated';

/// Thrown internally when the server reports this client is outdated, so the
/// sync cycle unwinds to [_runOnce] where the engine halts (rather than being
/// treated as a transient error and retried forever).
class _ClientOutdatedException implements Exception {
  const _ClientOutdatedException();
}

/// The end-to-end sync engine: pull → merge → recompute → push.
///
/// Lifecycle (owned by the AuthGate Provider):
///   * [start] subscribes to the server-side `getCounter` query and
///     schedules an initial sync.
///   * `notifyLocalWrite()` is called by anything that mutates the local
///     Drift DB; it debounces and triggers a sync cycle.
///   * `dispose()` cancels the subscription and any pending timer.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required AppDatabase db,
    required ConvexClient client,
    required ClientInfo clientInfo,
    this.onClientOutdated,
    this.pullPageLimit = 200,
    this.pushChunkLimit = 80,
    Duration writeDebounce = const Duration(milliseconds: 600),
  }) : _db = db,
       _client = client,
       _clientInfo = clientInfo,
       _writeDebounce = writeDebounce;

  final AppDatabase _db;
  final ConvexClient _client;
  final ClientInfo _clientInfo;
  final Duration _writeDebounce;

  /// Invoked when the backend rejects sync because this client is below the
  /// supported-version floor. Lets the app flip to the hard update prompt even
  /// when the client-side config gate was bypassed (e.g. a failed config fetch
  /// left the client fail-open). The engine halts itself before calling this.
  final void Function()? onClientOutdated;

  /// Hard cap on the `limit` passed to `sync.queries:pull`. Page size on the
  /// server is `min(this, args.limit ?? default)`. Keep below the Convex
  /// query item-read budget.
  final int pullPageLimit;

  /// Maximum upserts + tombstones combined inside a single push chunk. Each
  /// chunk is one Convex mutation; staying under the per-mutation read/write
  /// budget keeps us out of the "Too many bytes scanned" range.
  final int pushChunkLimit;

  SyncStatus _status = SyncStatus.idle;
  Object? _lastError;
  DateTime? _lastSyncedAt;
  BigInt _lastKnownRemoteCounter = BigInt.from(-1);
  int _pendingDirtyCorrections = 0;

  SyncStatus get status => _status;
  Object? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Timer? _debounce;
  Future<void>? _inFlight;
  bool _trailingTrigger = false;
  SubscriptionHandle? _counterSub;
  StreamSubscription<Object?>? _writeListener;
  bool _started = false;

  /// Set once the backend rejects this client as outdated. Terminal: the engine
  /// tears down its subscription/timers and refuses to start or schedule again
  /// for the rest of the process (the user must update the app).
  bool _halted = false;

  /// Wire up the counter subscription and kick off the first sync. Safe to
  /// call multiple times; subsequent calls are no-ops.
  Future<void> start() async {
    if (_started || _halted) return;
    _started = true;

    // Subscribe to the user's server counter. Any change → pull.
    try {
      _counterSub = await _client.subscribe(
        name: 'v1/sync/queries:getCounter',
        args: const {},
        onUpdate: (raw) {
          final value = decodeConvexResponse(raw);
          if (value is BigInt) {
            if (value > _lastKnownRemoteCounter) {
              _lastKnownRemoteCounter = value;
              _scheduleNow();
            }
          }
        },
        onError: (message, _) {
          debugPrint('sync: counter subscription error: $message');
        },
      );
    } catch (e) {
      debugPrint('sync: failed to subscribe to counter: $e');
    }

    // Listen for any local mutation to entity tables and trigger a debounced
    // sync. Writes the engine performs itself (merger / push-ack) happen
    // while `_inFlight != null` so we skip those to avoid feedback loops.
    _writeListener = _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.accounts,
            _db.categories,
            _db.tags,
            _db.transactions,
            _db.transactionTags,
            _db.savedFilters,
            _db.dashboardWidgets,
            _db.tombstones,
          ]),
        )
        .listen((_) {
          if (_inFlight != null) return;
          notifyLocalWrite();
        });

    _scheduleNow();
  }

  /// Called by every code path that writes a dirty row locally. Coalesces
  /// bursts of writes into a single sync cycle.
  void notifyLocalWrite() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(_writeDebounce, _scheduleNow);
  }

  /// Force a sync cycle to run immediately. Coalesces with any in-flight
  /// cycle: a trailing run is queued.
  Future<void> sync() {
    _debounce?.cancel();
    return _scheduleNow();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _counterSub?.cancel();
    _counterSub = null;
    _writeListener?.cancel();
    _writeListener = null;
    super.dispose();
  }

  // ─── Scheduler ───────────────────────────────────────────────────────────

  Future<void> _scheduleNow() {
    if (_halted) return Future.value();
    if (_inFlight != null) {
      _trailingTrigger = true;
      return _inFlight!;
    }
    final fut = _runOnce()
      ..whenComplete(() {
        _inFlight = null;
        if (_trailingTrigger) {
          _trailingTrigger = false;
          _scheduleNow();
        }
      });
    _inFlight = fut;
    return fut;
  }

  Future<void> _runOnce() async {
    _setStatus(SyncStatus.syncing, error: null);
    try {
      // One pull → push round. cursor_mismatch on push restarts the round.
      var attempts = 0;
      while (attempts < 5) {
        attempts += 1;
        await _pullDrain();
        await _recompute();
        final mismatched = await _pushAllChunks();
        if (!mismatched) break;
      }
      _lastSyncedAt = DateTime.now();
      // Persist a heartbeat so the UI can show "Last synced 1 min ago".
      await (_db.update(
        _db.syncState,
      )..where((s) => s.id.equals('singleton'))).write(
        SyncStateCompanion(
          lastSyncedAt: Value(
            BigInt.from(DateTime.now().millisecondsSinceEpoch),
          ),
        ),
      );
      _setStatus(SyncStatus.synced, error: null);
    } on _ClientOutdatedException {
      debugPrint('sync: backend rejected client as outdated — halting sync');
      _haltForOutdatedClient();
    } catch (e, st) {
      debugPrint('sync: runOnce failed: $e\n$st');
      _setStatus(SyncStatus.error, error: e);
    }
  }

  /// Tear down the engine after a `client_outdated` rejection: cancel the
  /// counter subscription, write listener and debounce timer so no further
  /// cycles run, then notify the app so it can surface the update prompt.
  void _haltForOutdatedClient() {
    _halted = true;
    _debounce?.cancel();
    _counterSub?.cancel();
    _counterSub = null;
    _writeListener?.cancel();
    _writeListener = null;
    _setStatus(SyncStatus.error, error: const _ClientOutdatedException());
    onClientOutdated?.call();
  }

  void _setStatus(SyncStatus status, {Object? error}) {
    _status = status;
    _lastError = error;
    notifyListeners();
  }

  // ─── Pull ────────────────────────────────────────────────────────────────

  Future<void> _pullDrain() async {
    final merger = PullPageMerger(_db);
    BigInt since = await _readLastServerSeq();

    BigInt finalCurrentCounter = since;
    bool drained = false;
    int safety = 0;
    while (!drained) {
      safety += 1;
      if (safety > 10000) {
        throw StateError('sync: pull loop exceeded 10k iterations');
      }

      final raw = await _client.query('v1/sync/queries:pull', {
        'since': prepareArgValue(since),
        'limit': pullPageLimit,
        'platform': _clientInfo.platform,
        'appVersion': _clientInfo.appVersion,
      });
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) {
        throw StateError('sync: malformed pull response: $raw');
      }
      if (decoded['error'] == _clientOutdatedError) {
        throw const _ClientOutdatedException();
      }
      final rows = (decoded['rows'] as List).cast<Map<String, Object?>>();
      final tombstones = (decoded['tombstones'] as List)
          .cast<Map<String, Object?>>();
      final hasMore = decoded['hasMore'] as bool;
      final nextCursor = decoded['nextCursor'];
      final currentCounter = decoded['currentCounter'] as BigInt;
      finalCurrentCounter = currentCounter;

      await merger.applyPage(rows: rows, tombstones: tombstones);

      if (!hasMore) {
        drained = true;
      } else {
        if (nextCursor is! BigInt) {
          throw StateError(
            'sync: pull says hasMore=true but nextCursor is not int64: '
            '${decoded['nextCursor']}',
          );
        }
        if (nextCursor <= since) {
          throw StateError(
            'sync: pull cursor did not advance (since=$since, nextCursor=$nextCursor)',
          );
        }
        since = nextCursor;
      }
    }

    // Only commit last_server_seq after every page is applied (spec
    // §"Importante. No avanzar last_server_seq hasta drenar todas las
    // páginas").
    await _writeLastServerSeq(finalCurrentCounter);
    _lastKnownRemoteCounter = finalCurrentCounter;
  }

  Future<BigInt> _readLastServerSeq() async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.id.equals('singleton'))).getSingleOrNull();
    if (row != null) return row.lastServerSeq;
    await _db
        .into(_db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: const Value('singleton'),
            lastServerSeq: Value(BigInt.zero),
          ),
        );
    return BigInt.zero;
  }

  Future<void> _writeLastServerSeq(BigInt value) async {
    await (_db.update(_db.syncState)..where((s) => s.id.equals('singleton')))
        .write(SyncStateCompanion(lastServerSeq: Value(value)));
  }

  // ─── Recompute ───────────────────────────────────────────────────────────

  Future<void> _recompute() async {
    final n = await BalanceAdjustmentRecomputer(_db).recompute();
    _pendingDirtyCorrections = n;
  }

  // ─── Push ────────────────────────────────────────────────────────────────

  /// Returns `true` if we hit `cursor_mismatch` and need to re-pull. Returns
  /// `false` when there's nothing left to push or every chunk committed.
  Future<bool> _pushAllChunks() async {
    while (true) {
      final chunk = await _collectChunk();
      if (chunk.isEmpty) return false;

      final expected = await _readLastServerSeq();
      final result = await _sendChunk(expected: expected, chunk: chunk);
      if (result.cursorMismatch) {
        return true;
      }
      await _applyChunkAck(chunk, ackedSeq: result.newSeq!);
    }
  }

  Future<_Chunk> _collectChunk() async {
    final chunk = _Chunk();

    // Catalog first (accounts → categories → tags), then transactions, then
    // joins. Tombstones interleaved by table.
    final dirtyAccounts =
        await (_db.select(_db.accounts)
              ..where((a) => a.dirty.equals(true))
              ..limit(pushChunkLimit))
            .get();
    chunk.accounts.addAll(dirtyAccounts);
    if (chunk.size >= pushChunkLimit) return chunk;

    final dirtyCategories =
        await (_db.select(_db.categories)
              ..where((c) => c.dirty.equals(true))
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.categories.addAll(dirtyCategories);
    if (chunk.size >= pushChunkLimit) return chunk;

    final dirtyTags =
        await (_db.select(_db.tags)
              ..where((t) => t.dirty.equals(true))
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.tags.addAll(dirtyTags);
    if (chunk.size >= pushChunkLimit) return chunk;

    // Dashboard layout: saved filters before widgets (a widget's `filterId`
    // soft-references a saved filter), mirroring accounts → transactions.
    final dirtySavedFilters =
        await (_db.select(_db.savedFilters)
              ..where((f) => f.dirty.equals(true))
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.savedFilters.addAll(dirtySavedFilters);
    if (chunk.size >= pushChunkLimit) return chunk;

    final dirtyDashboardWidgets =
        await (_db.select(_db.dashboardWidgets)
              ..where((w) => w.dirty.equals(true))
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.dashboardWidgets.addAll(dirtyDashboardWidgets);
    if (chunk.size >= pushChunkLimit) return chunk;

    final dirtyTxns =
        await (_db.select(_db.transactions)
              ..where((t) => t.dirty.equals(true))
              ..orderBy([(t) => OrderingTerm.asc(t.date)])
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.transactions.addAll(dirtyTxns);
    if (chunk.size >= pushChunkLimit) return chunk;

    // Only push joins whose transaction will exist on the server after this
    // chunk: either it's already on the server (i.e. local row is
    // dirty=false) or it goes in this chunk. Otherwise we'd get an FK
    // validation error.
    final pendingTxnIdsInChunk = chunk.transactions.map((t) => t.id).toSet();
    final dirtyJoinsAll =
        await (_db.select(_db.transactionTags)
              ..where((j) => j.dirty.equals(true))
              ..limit(pushChunkLimit * 2))
            .get();
    for (final j in dirtyJoinsAll) {
      if (chunk.size >= pushChunkLimit) break;
      if (pendingTxnIdsInChunk.contains(j.transactionId)) {
        chunk.transactionTags.add(j);
        continue;
      }
      final remoteTxn = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(j.transactionId))).getSingleOrNull();
      // Already-on-server: not dirty and not absent.
      if (remoteTxn != null && !remoteTxn.dirty) {
        chunk.transactionTags.add(j);
      }
      // else: skip; this join will be picked up in a later chunk after its
      // transaction is on the server.
    }

    final dirtyTombs =
        await (_db.select(_db.tombstones)
              ..where((t) => t.dirty.equals(true))
              ..limit(pushChunkLimit - chunk.size))
            .get();
    chunk.tombstones.addAll(dirtyTombs);

    return chunk;
  }

  Future<_PushResult> _sendChunk({
    required BigInt expected,
    required _Chunk chunk,
  }) async {
    final args = <String, Object?>{
      'expectedServerSeq': prepareArgValue(expected),
      'upserts': prepareArgValue({
        if (chunk.accounts.isNotEmpty)
          'accounts': chunk.accounts.map(_serializeAccount).toList(),
        if (chunk.categories.isNotEmpty)
          'categories': chunk.categories.map(_serializeCategory).toList(),
        if (chunk.tags.isNotEmpty)
          'tags': chunk.tags.map(_serializeTag).toList(),
        if (chunk.savedFilters.isNotEmpty)
          'savedFilters': chunk.savedFilters
              .map(_serializeSavedFilter)
              .toList(),
        if (chunk.dashboardWidgets.isNotEmpty)
          'dashboardWidgets': chunk.dashboardWidgets
              .map(_serializeDashboardWidget)
              .toList(),
        if (chunk.transactions.isNotEmpty)
          'transactions': chunk.transactions
              .map(_serializeTransaction)
              .toList(),
        if (chunk.transactionTags.isNotEmpty)
          'transactionTags': chunk.transactionTags
              .map(_serializeTransactionTag)
              .toList(),
      }),
      if (chunk.tombstones.isNotEmpty)
        'tombstones': prepareArgValue(
          chunk.tombstones.map(_serializeTombstone).toList(),
        ),
      'platform': _clientInfo.platform,
      'appVersion': _clientInfo.appVersion,
    };

    final raw = await _client.mutation(
      name: 'v1/sync/mutations:push',
      args: args,
    );
    final decoded = decodeConvexResponse(raw);
    if (decoded is! Map) {
      throw StateError('sync: malformed push response: $raw');
    }
    final ok = decoded['ok'] == true;
    if (!ok) {
      final err = decoded['error'];
      if (err == _clientOutdatedError) {
        throw const _ClientOutdatedException();
      }
      if (err == 'cursor_mismatch') {
        final cc = decoded['currentCounter'];
        if (cc is BigInt) _lastKnownRemoteCounter = cc;
        return _PushResult.cursorMismatch();
      }
      throw StateError('sync: push failed: $decoded');
    }
    return _PushResult.ok(newSeq: decoded['newSeq'] as BigInt);
  }

  Future<void> _applyChunkAck(_Chunk chunk, {required BigInt ackedSeq}) async {
    await _db.transaction(() async {
      for (final a in chunk.accounts) {
        // Spec §"Si local.updatedAt == payload.updatedAt → dirty=false. Si
        // no → se queda dirty=true". Re-fetch to compare.
        final cur = await (_db.select(
          _db.accounts,
        )..where((row) => row.id.equals(a.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == a.updatedAt) {
          await (_db.update(_db.accounts)..where((row) => row.id.equals(a.id)))
              .write(const AccountsCompanion(dirty: Value(false)));
        }
      }
      for (final c in chunk.categories) {
        final cur = await (_db.select(
          _db.categories,
        )..where((row) => row.id.equals(c.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == c.updatedAt) {
          await (_db.update(_db.categories)
                ..where((row) => row.id.equals(c.id)))
              .write(const CategoriesCompanion(dirty: Value(false)));
        }
      }
      for (final tg in chunk.tags) {
        final cur = await (_db.select(
          _db.tags,
        )..where((row) => row.id.equals(tg.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == tg.updatedAt) {
          await (_db.update(_db.tags)..where((row) => row.id.equals(tg.id)))
              .write(const TagsCompanion(dirty: Value(false)));
        }
      }
      for (final f in chunk.savedFilters) {
        final cur = await (_db.select(
          _db.savedFilters,
        )..where((row) => row.id.equals(f.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == f.updatedAt) {
          await (_db.update(_db.savedFilters)
                ..where((row) => row.id.equals(f.id)))
              .write(const SavedFiltersCompanion(dirty: Value(false)));
        }
      }
      for (final w in chunk.dashboardWidgets) {
        final cur = await (_db.select(
          _db.dashboardWidgets,
        )..where((row) => row.id.equals(w.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == w.updatedAt) {
          await (_db.update(_db.dashboardWidgets)
                ..where((row) => row.id.equals(w.id)))
              .write(const DashboardWidgetsCompanion(dirty: Value(false)));
        }
      }
      for (final t in chunk.transactions) {
        final cur = await (_db.select(
          _db.transactions,
        )..where((row) => row.id.equals(t.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == t.updatedAt) {
          await (_db.update(_db.transactions)
                ..where((row) => row.id.equals(t.id)))
              .write(const TransactionsCompanion(dirty: Value(false)));
        }
      }
      for (final j in chunk.transactionTags) {
        final cur = await (_db.select(
          _db.transactionTags,
        )..where((row) => row.id.equals(j.id))).getSingleOrNull();
        if (cur != null && cur.updatedAt == j.updatedAt) {
          await (_db.update(_db.transactionTags)
                ..where((row) => row.id.equals(j.id)))
              .write(const TransactionTagsCompanion(dirty: Value(false)));
        }
      }
      for (final t in chunk.tombstones) {
        final cur =
            await (_db.select(_db.tombstones)..where(
                  (row) =>
                      row.entityTable.equals(t.entityTable) &
                      row.entityId.equals(t.entityId),
                ))
                .getSingleOrNull();
        if (cur != null && cur.deletedAt == t.deletedAt) {
          await (_db.update(_db.tombstones)..where(
                (row) =>
                    row.entityTable.equals(t.entityTable) &
                    row.entityId.equals(t.entityId),
              ))
              .write(const TombstonesCompanion(dirty: Value(false)));
        }
      }
    });

    // Advance our local cursor to the new seq so the next pull starts
    // beyond this chunk's rows (we already know what they are, no need to
    // re-pull them).
    await _writeLastServerSeq(ackedSeq);
    _lastKnownRemoteCounter = ackedSeq;
  }

  // ─── Wire-format serializers ─────────────────────────────────────────────

  Map<String, Object?> _serializeAccount(Account row) => {
    'id': row.id,
    'name': row.name,
    'currency': row.currency,
    if (row.description != null) 'description': row.description,
    'color': row.color,
    'icon': row.icon,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeCategory(Category row) => {
    'id': row.id,
    'name': row.name,
    if (row.description != null) 'description': row.description,
    'color': row.color,
    'icon': row.icon,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeTag(Tag row) => {
    'id': row.id,
    'name': row.name,
    if (row.description != null) 'description': row.description,
    if (row.parentId != null) 'parentId': row.parentId,
    'color': row.color,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeSavedFilter(SavedFilter row) => {
    'id': row.id,
    'name': row.name,
    'config': row.config,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeDashboardWidget(DashboardWidget row) => {
    'id': row.id,
    'type': row.type,
    if (row.filterId != null) 'filterId': row.filterId,
    'position': row.position,
    'width': row.width,
    'options': row.options,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeTransaction(Transaction row) => {
    'id': row.id,
    'type': row.type,
    'name': row.name,
    if (row.description != null) 'description': row.description,
    'status': row.status,
    'date': row.date,
    'dateConfirmed': row.dateConfirmed,
    'timeStatus': row.timeStatus.name,
    'accountId': row.accountId,
    'categoryId': row.categoryId,
    'amount': row.amount,
    'currency': row.currency,
    if (row.toAccountId != null) 'toAccountId': row.toAccountId,
    if (row.toAmount != null) 'toAmount': row.toAmount,
    if (row.toCurrency != null) 'toCurrency': row.toCurrency,
    if (row.exchangeRate != null) 'exchangeRate': row.exchangeRate,
    if (row.balanceAfter != null) 'balanceAfter': row.balanceAfter,
    'isArchived': row.archived,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeTransactionTag(TransactionTag row) => {
    'id': row.id,
    'transactionId': row.transactionId,
    'tagId': row.tagId,
    'createdAt': row.createdAt,
    'updatedAt': row.updatedAt,
  };

  Map<String, Object?> _serializeTombstone(Tombstone row) => {
    'tableName': row.entityTable,
    'entityId': row.entityId,
    'deletedAt': row.deletedAt,
  };

  @visibleForTesting
  int get pendingDirtyCorrections => _pendingDirtyCorrections;
}

class _Chunk {
  final List<Account> accounts = [];
  final List<Category> categories = [];
  final List<Tag> tags = [];
  final List<SavedFilter> savedFilters = [];
  final List<DashboardWidget> dashboardWidgets = [];
  final List<Transaction> transactions = [];
  final List<TransactionTag> transactionTags = [];
  final List<Tombstone> tombstones = [];

  int get size =>
      accounts.length +
      categories.length +
      tags.length +
      savedFilters.length +
      dashboardWidgets.length +
      transactions.length +
      transactionTags.length +
      tombstones.length;

  bool get isEmpty => size == 0;
}

class _PushResult {
  _PushResult.ok({required this.newSeq}) : cursorMismatch = false;
  _PushResult.cursorMismatch() : newSeq = null, cursorMismatch = true;
  final BigInt? newSeq;
  final bool cursorMismatch;
}
