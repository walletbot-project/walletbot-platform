import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';

import '../sync/wire.dart';
import 'voice_session_repository.dart';

/// Best-effort replication of the durable local voice log.
///
/// Local commits are authoritative for export. Remote failures never block a
/// Live session; unsynced rows remain queued and are retried with backoff.
class VoiceSessionRemoteSync {
  VoiceSessionRemoteSync({
    required VoiceSessionRepository repository,
    ConvexClient? client,
    this.batchSize = 50,
  }) : _repository = repository,
       _client = client ?? ConvexClient.instance;

  final VoiceSessionRepository _repository;
  final ConvexClient _client;
  final int batchSize;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false;
  bool _trailing = false;

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
      return _inFlight;
    }
    final run = _drain();
    _inFlight = run;
    try {
      await run;
    } catch (error, stackTrace) {
      debugPrint('voice sync: $error\n$stackTrace');
      schedule(delay: const Duration(seconds: 5));
    } finally {
      _inFlight = null;
      if (_trailing && !_disposed) {
        _trailing = false;
        schedule(delay: Duration.zero);
      }
    }
  }

  Future<void> _drain() async {
    while (!_disposed) {
      final pending = await _repository.unsyncedEvents(limit: batchSize);
      if (pending.isEmpty) return;
      final sessionId = pending.first.sessionId;
      final events = pending
          .where((event) => event.sessionId == sessionId)
          .toList(growable: false);
      final session = await _repository.getSession(sessionId);
      if (session == null) {
        await _repository.markEventsSynced(
          events.map((event) => event.id).toList(growable: false),
        );
        continue;
      }

      await _client.mutation(
        name: 'v1/voice/sessions:appendEvents',
        args:
            (prepareArgValue({
                  'session': {
                    'id': session.id,
                    'model': session.model,
                    'status': session.status,
                    'startedAt': session.startedAt,
                    'updatedAt': session.updatedAt,
                    if (session.endedAt != null) 'endedAt': session.endedAt,
                    'endedExplicitly': session.endedExplicitly,
                  },
                  'events': events
                      .map(
                        (event) => {
                          'id': event.id,
                          'sequence': event.sequence,
                          'occurredAt': event.occurredAt,
                          'type': event.type,
                          'direction': event.direction,
                          if (event.modality != null)
                            'modality': event.modality,
                          'payloadJson': event.payloadJson,
                          if (event.rawJson != null)
                            'rawJson': _redactRemoteSecrets(event.rawJson!),
                          if (event.binaryData != null)
                            'binaryByteLength': event.binaryData!.length,
                          if (event.binaryMimeType != null)
                            'binaryMimeType': event.binaryMimeType,
                        },
                      )
                      .toList(growable: false),
                })
                as Map<String, Object?>),
      );

      await _repository.markEventsSynced(
        events.map((event) => event.id).toList(growable: false),
      );
      if (!await _repository.hasUnsyncedEvents(sessionId)) {
        await _repository.markSessionSynced(sessionId);
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    try {
      await flush();
    } finally {
      _disposed = true;
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
