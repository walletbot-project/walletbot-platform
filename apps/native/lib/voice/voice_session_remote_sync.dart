import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../convex/convex_client.dart';
import '../database.dart';
import 'voice_session_repository.dart';

/// Best-effort replication of the durable local voice log.
///
/// Local commits are authoritative for export. Remote failures never block a
/// Live session; unsynced rows remain queued and are retried with backoff.
class VoiceSessionRemoteSync {
  VoiceSessionRemoteSync({
    required VoiceSessionRepository repository,
    required this.ownerId,
    required ConvexClient? client,
    this.batchSize = 50,
  }) : _repository = repository,
       _client = client;

  final VoiceSessionRepository _repository;

  /// Null only without a Convex transport (widget tests): the drain then
  /// fails like any offline flush and the outbox rows stay pending.
  final ConvexClient? _client;

  ConvexClient get _requireClient {
    final client = _client;
    if (client == null) {
      throw StateError('voice sync: no ConvexClient wired');
    }
    return client;
  }

  final String ownerId;
  final int batchSize;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false;
  bool _trailing = false;

  /// Bound on waiting for a socket to send a replication mutation on.
  ///
  /// The Convex client queues a mutation with no socket for as long as it
  /// takes, which is what makes an offline write survive to the next
  /// connection. This outbox does not need that: the rows stay
  /// `remoteSynced: false` until the server acknowledges them, so the durable
  /// log *is* the retry, and an unbounded wait only buys a drain that can
  /// never end. Without this bound a drain started offline pinned [_inFlight]
  /// forever, which silently swallowed every later flush and hung
  /// [dispose] with it.
  static const _connectTimeout = Duration(seconds: 10);

  static const _mutationOptions = CallOptions(connectTimeout: _connectTimeout);

  /// Bound on how long teardown waits for the drain in flight. Ending a voice
  /// session or switching account must not wait on Convex.
  static const _disposeGrace = Duration(seconds: 2);

  /// Rows per mutation. The old cap of 50 was set when a batch was really a
  /// fragment of a page; with the query scoped to one session a batch is a
  /// batch, and each row costs the server one indexed lookup plus one insert.
  static const _maxRowsPerBatch = 200;

  /// Byte budget per mutation, well under Convex's 1 MB argument limit. Row
  /// sizes are wildly uneven because `rawJson` carries whole protocol frames,
  /// so a row count on its own is either wasteful or too large depending on
  /// what happens to be in them.
  static const _maxBytesPerBatch = 512 * 1024;

  /// Batches in flight at once. Convex conflicts two mutations that write the
  /// same document; batches after the first carry an unchanged session
  /// payload, and the server now skips that write, so they overlap only on
  /// reads.
  static const _maxConcurrentBatches = 4;

  /// Batches per pass before yielding. The outbox is a backlog, not a
  /// deadline: a pass takes a bite and reschedules rather than sitting on the
  /// radio for a whole conversation.
  static const _maxBatchesPerPass = 8;

  /// Fixed per-event wire cost (ids, sequence, timestamps, JSON punctuation)
  /// on top of the two JSON strings that dominate.
  static const _eventOverhead = 256;

  void schedule({Duration delay = const Duration(seconds: 1)}) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_inFlight != null) {
      _trailing = true;
      // Join the in-flight drain without leaking its error to this caller:
      // the flush() call that started it already logs the failure and
      // schedules the retry.
      return _inFlight!.catchError((Object _) {});
    }
    final stopwatch = Stopwatch()..start();
    var rows = 0;
    final run = _drain((batch) => rows += batch);
    _inFlight = run;
    try {
      await run;
      if (rows > 0) {
        debugPrint(
          '[voice sync] drained $rows rows in ${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } catch (error, stackTrace) {
      // Each row is one Convex round trip, so the row count is what says
      // whether a slow drain was a slow server or simply a lot of backlog.
      debugPrint(
        '[voice sync] failed after $rows rows in '
        '${stopwatch.elapsedMilliseconds}ms: $error\n$stackTrace',
      );
      schedule(delay: const Duration(seconds: 5));
    } finally {
      _inFlight = null;
      if (_trailing && !_disposed) {
        _trailing = false;
        schedule(delay: Duration.zero);
      }
    }
  }

  Future<void> _drain(void Function(int rows) onBatch) async {
    var batchesThisPass = 0;
    while (!_disposed) {
      if (batchesThisPass >= _maxBatchesPerPass) {
        schedule(delay: const Duration(seconds: 2));
        return;
      }
      final sessionId = await _repository.nextUnsyncedEventSessionId();
      if (sessionId == null) {
        await _drainSessionsWithoutEvents(onBatch);
        return;
      }
      final pending = await _repository.unsyncedEventsForSession(
        sessionId: sessionId,
        limit: _maxRowsPerBatch * _maxConcurrentBatches,
      );
      if (pending.isEmpty) continue;
      final session = await _repository.getSession(sessionId);
      if (session == null) {
        await _repository.markEventsSynced(
          pending.map((event) => event.id).toList(growable: false),
        );
        continue;
      }
      // Take only what the pass still has room for. Capping here rather than
      // just at the top of the loop matters when the byte budget splits one
      // page into many batches: otherwise a single iteration blows straight
      // through the cap before anything gets to check it.
      final batches = _split(
        pending,
      ).take(_maxBatchesPerPass - batchesThisPass).toList();
      batchesThisPass += batches.length;
      await _sendBatches(session, batches, onBatch);
      if (!await _repository.hasUnsyncedEvents(sessionId)) {
        await _repository.markSessionSyncedIfUnchanged(
          sessionId,
          session.updatedAt,
        );
      }
    }
  }

  /// Sessions whose row changed but whose events are all replicated already
  /// (status flips, the explicit end). One mutation each, no events attached.
  Future<void> _drainSessionsWithoutEvents(
    void Function(int rows) onBatch,
  ) async {
    final sessions = await _repository.unsyncedSessions(limit: batchSize);
    for (final session in sessions) {
      if (_disposed) return;
      await _requireClient.mutation<Object?>('v1/voice/sessions:appendEvents', {
        'ownerId': ownerId,
        'session': _sessionPayload(session),
        'events': <Object?>[],
      }, options: _mutationOptions);
      await _repository.markSessionSyncedIfUnchanged(
        session.id,
        session.updatedAt,
      );
      onBatch(0);
    }
  }

  Future<void> _sendBatches(
    VoiceSession session,
    List<List<VoiceSessionEvent>> batches,
    void Function(int rows) onBatch,
  ) async {
    // The first batch goes alone because it is the one that may still have to
    // create or update the session document. Once it lands, every later batch
    // carries a payload the server finds unchanged and therefore does not
    // write, which is what lets them go out together without conflicting.
    await _sendBatch(session, batches.first, onBatch);
    for (var i = 1; i < batches.length; i += _maxConcurrentBatches) {
      if (_disposed) return;
      final group = batches.skip(i).take(_maxConcurrentBatches);
      // Waits for all of them even when one fails: the ones that succeeded
      // have already marked their rows, and the failure resurfaces to
      // flush(), which schedules the retry for whatever is left.
      await Future.wait(
        group.map((batch) => _sendBatch(session, batch, onBatch)),
      );
    }
  }

  Future<void> _sendBatch(
    VoiceSession session,
    List<VoiceSessionEvent> events,
    void Function(int rows) onBatch,
  ) async {
    await _requireClient.mutation<Object?>('v1/voice/sessions:appendEvents', {
      'ownerId': ownerId,
      'session': _sessionPayload(session),
      'events': events.map(_eventPayload).toList(growable: false),
    }, options: _mutationOptions);
    await _repository.markEventsSynced(
      events.map((event) => event.id).toList(growable: false),
    );
    onBatch(events.length);
  }

  /// Splits pending rows into mutation-sized batches by count and by bytes.
  /// A single row over the budget still goes on its own: dropping it would
  /// stall the outbox behind it forever.
  List<List<VoiceSessionEvent>> _split(List<VoiceSessionEvent> events) {
    final batches = <List<VoiceSessionEvent>>[];
    var current = <VoiceSessionEvent>[];
    var bytes = 0;
    for (final event in events) {
      final size = _wireSize(event);
      if (current.isNotEmpty &&
          (current.length >= _maxRowsPerBatch ||
              bytes + size > _maxBytesPerBatch)) {
        batches.add(current);
        current = <VoiceSessionEvent>[];
        bytes = 0;
      }
      current.add(event);
      bytes += size;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// String length counts UTF-16 units rather than the UTF-8 bytes that go on
  /// the wire, so this reads low for non-ASCII text. The budget is half the
  /// hard limit, which covers the gap.
  int _wireSize(VoiceSessionEvent event) =>
      event.payloadJson.length + (event.rawJson?.length ?? 0) + _eventOverhead;

  Map<String, Object?> _eventPayload(VoiceSessionEvent event) => {
    'id': event.id,
    'sequence': event.sequence,
    'occurredAt': event.occurredAt,
    'type': event.type,
    'direction': event.direction,
    if (event.modality != null) 'modality': event.modality,
    'payloadJson': event.payloadJson,
    if (event.rawJson != null) 'rawJson': _redactRemoteSecrets(event.rawJson!),
    if (event.binaryData != null) 'binaryByteLength': event.binaryData!.length,
    if (event.binaryMimeType != null) 'binaryMimeType': event.binaryMimeType,
  };

  Map<String, Object?> _sessionPayload(VoiceSession session) => {
    'id': session.id,
    'model': session.model,
    'status': session.status,
    'startedAt': session.startedAt,
    'updatedAt': session.updatedAt,
    if (session.endedAt != null) 'endedAt': session.endedAt,
    'endedExplicitly': session.endedExplicitly,
  };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _trailing = false;
    _timer?.cancel();
    _timer = null;
    final inFlight = _inFlight;
    if (inFlight == null) return;
    try {
      // Bounded, not awaited outright: a drain sitting on a mutation the
      // server has not acknowledged would otherwise hold teardown for the
      // client's full 30 s operation timeout. Whatever is unacknowledged is
      // still in the outbox and replicates on the next run.
      await inFlight.timeout(_disposeGrace);
    } on TimeoutException {
      debugPrint('[voice sync] dispose left a drain running');
    } catch (_) {
      // flush() already logged the failure; local outbox rows remain pending.
    }
  }

  String _redactRemoteSecrets(String rawJson) {
    Object? redact(Object? value) {
      if (value is List) return value.map(redact).toList(growable: false);
      if (value is! Map) return value;
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString():
              const {'handle', 'newHandle'}.contains(entry.key.toString())
              ? '<redacted>'
              : redact(entry.value),
      };
    }

    return jsonEncode(redact(jsonDecode(rawJson)));
  }
}
