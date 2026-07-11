import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';

const _resumeHandleLifetime = Duration(hours: 2);

/// Durable, append-only storage for Live API sessions.
///
/// Every observable client/server event is committed locally before it is
/// eligible for remote replication. PCM is kept in [binaryData] locally; the
/// remote wire format only includes its mime type and byte length.
class VoiceSessionRepository {
  VoiceSessionRepository(this.db, {this.remoteEnabled = false});

  final AppDatabase db;
  final bool remoteEnabled;
  final Uuid _uuid = const Uuid();
  Future<void> _writeTail = Future.value();
  final Map<String, int> _nextSequences = {};

  Future<VoiceSession> openOrCreate({required String model}) => _serial(
    () async {
      final now = DateTime.now();
      final active =
          await (db.select(db.voiceSessions)
                ..where((row) => row.status.isNotIn(const ['ended', 'expired']))
                ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (active != null) {
        final handleAt = active.resumeHandleUpdatedAt?.toInt();
        final canResume =
            active.resumeHandle != null &&
            handleAt != null &&
            now.difference(DateTime.fromMillisecondsSinceEpoch(handleAt)) <
                _resumeHandleLifetime;
        if (canResume) {
          await (db.update(
            db.voiceSessions,
          )..where((row) => row.id.equals(active.id))).write(
            VoiceSessionsCompanion(
              status: const Value('active'),
              updatedAt: Value(BigInt.from(now.millisecondsSinceEpoch)),
              remoteSynced: remoteEnabled
                  ? const Value(false)
                  : const Value.absent(),
            ),
          );
          return (db.select(
            db.voiceSessions,
          )..where((row) => row.id.equals(active.id))).getSingle();
        }

        await (db.update(
          db.voiceSessions,
        )..where((row) => row.id.equals(active.id))).write(
          VoiceSessionsCompanion(
            status: const Value('expired'),
            endedAt: Value(BigInt.from(now.millisecondsSinceEpoch)),
            updatedAt: Value(BigInt.from(now.millisecondsSinceEpoch)),
            remoteSynced: remoteEnabled
                ? const Value(false)
                : const Value.absent(),
          ),
        );
      }

      final id = _uuid.v4();
      final millis = BigInt.from(now.millisecondsSinceEpoch);
      await db
          .into(db.voiceSessions)
          .insert(
            VoiceSessionsCompanion.insert(
              id: id,
              model: model,
              status: 'active',
              startedAt: millis,
              updatedAt: millis,
              remoteEnabled: Value(remoteEnabled),
              remoteSynced: Value(!remoteEnabled),
            ),
          );
      return (db.select(
        db.voiceSessions,
      )..where((row) => row.id.equals(id))).getSingle();
    },
  );

  Future<void> appendEvent({
    required String sessionId,
    required DateTime occurredAt,
    required String type,
    required String direction,
    String? modality,
    Map<String, Object?> payload = const {},
    Map<String, Object?>? raw,
    Uint8List? binaryData,
    String? binaryMimeType,
  }) => _serial(() async {
    final sequence = await _takeSequence(sessionId);
    final updatedAt = await _monotonicUpdatedAt(sessionId, occurredAt);
    await db
        .into(db.voiceSessionEvents)
        .insert(
          VoiceSessionEventsCompanion.insert(
            id: _uuid.v4(),
            sessionId: sessionId,
            sequence: sequence,
            occurredAt: BigInt.from(occurredAt.millisecondsSinceEpoch),
            type: type,
            direction: direction,
            modality: Value(modality),
            payloadJson: jsonEncode(payload),
            rawJson: Value(raw == null ? null : jsonEncode(raw)),
            binaryData: Value(binaryData),
            binaryMimeType: Value(binaryMimeType),
            remoteSynced: Value(!remoteEnabled),
          ),
        );
    await (db.update(
      db.voiceSessions,
    )..where((row) => row.id.equals(sessionId))).write(
      VoiceSessionsCompanion(
        updatedAt: Value(updatedAt),
        remoteSynced: remoteEnabled ? const Value(false) : const Value.absent(),
      ),
    );
  });

  Future<void> updateResumeHandle({
    required String sessionId,
    required String handle,
    required DateTime at,
  }) => _serial(() async {
    final updatedAt = await _monotonicUpdatedAt(sessionId, at);
    await (db.update(
      db.voiceSessions,
    )..where((row) => row.id.equals(sessionId))).write(
      VoiceSessionsCompanion(
        resumeHandle: Value(handle),
        resumeHandleUpdatedAt: Value(BigInt.from(at.millisecondsSinceEpoch)),
        updatedAt: Value(updatedAt),
        remoteSynced: remoteEnabled ? const Value(false) : const Value.absent(),
      ),
    );
  });

  Future<void> markStatus(String sessionId, String status) => _serial(() async {
    final now = DateTime.now();
    await (db.update(
      db.voiceSessions,
    )..where((row) => row.id.equals(sessionId))).write(
      VoiceSessionsCompanion(
        status: Value(status),
        updatedAt: Value(BigInt.from(now.millisecondsSinceEpoch)),
        remoteSynced: remoteEnabled ? const Value(false) : const Value.absent(),
      ),
    );
  });

  Future<void> endExplicitly(String sessionId) => _serial(() async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await (db.update(
      db.voiceSessions,
    )..where((row) => row.id.equals(sessionId))).write(
      VoiceSessionsCompanion(
        status: const Value('ended'),
        endedAt: Value(now),
        endedExplicitly: const Value(true),
        updatedAt: Value(now),
        remoteSynced: remoteEnabled ? const Value(false) : const Value.absent(),
      ),
    );
  });

  Future<List<VoiceSessionEvent>> unsyncedEvents({int limit = 50}) =>
      (db.select(db.voiceSessionEvents)
            ..where((row) => row.remoteSynced.equals(false))
            ..orderBy([
              (row) => OrderingTerm.asc(row.occurredAt),
              (row) => OrderingTerm.asc(row.sequence),
            ])
            ..limit(limit))
          .get();

  Future<List<VoiceSession>> unsyncedSessions({int limit = 50}) =>
      (db.select(db.voiceSessions)
            ..where((row) => row.remoteSynced.equals(false))
            ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)])
            ..limit(limit))
          .get();

  Future<bool> hasUnsyncedEvents(String sessionId) async {
    final row =
        await (db.select(db.voiceSessionEvents)
              ..where(
                (event) =>
                    event.sessionId.equals(sessionId) &
                    event.remoteSynced.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<VoiceSession?> getSession(String id) => (db.select(
    db.voiceSessions,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<void> markEventsSynced(List<String> eventIds) => _serial(() async {
    if (eventIds.isEmpty) return;
    await (db.update(db.voiceSessionEvents)
          ..where((row) => row.id.isIn(eventIds)))
        .write(const VoiceSessionEventsCompanion(remoteSynced: Value(true)));
  });

  Future<void> markSessionSynced(String sessionId) => _serial(() async {
    await (db.update(db.voiceSessions)
          ..where((row) => row.id.equals(sessionId)))
        .write(const VoiceSessionsCompanion(remoteSynced: Value(true)));
  });

  /// Complete machine-readable export. Binary PCM is base64 encoded so the
  /// resulting JSON is self-contained and lossless.
  Future<String> exportSessionJson(String sessionId) async {
    await flush();
    final session = await getSession(sessionId);
    if (session == null) throw StateError('Unknown voice session: $sessionId');
    final events =
        await (db.select(db.voiceSessionEvents)
              ..where((row) => row.sessionId.equals(sessionId))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();

    Object? decode(String? value) => value == null ? null : jsonDecode(value);
    String iso(BigInt value) => DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    ).toIso8601String();

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'walletbot.voice-session',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'session': {
        'id': session.id,
        'model': session.model,
        'status': session.status,
        'startedAt': iso(session.startedAt),
        'updatedAt': iso(session.updatedAt),
        if (session.endedAt != null) 'endedAt': iso(session.endedAt!),
        'endedExplicitly': session.endedExplicitly,
        if (session.resumeHandle != null) 'resumeHandle': session.resumeHandle,
        if (session.resumeHandleUpdatedAt != null)
          'resumeHandleUpdatedAt': iso(session.resumeHandleUpdatedAt!),
        'remoteEnabled': session.remoteEnabled,
        'remoteSynced': session.remoteSynced,
      },
      'events': events
          .map(
            (event) => {
              'id': event.id,
              'sequence': event.sequence,
              'occurredAt': iso(event.occurredAt),
              'type': event.type,
              'direction': event.direction,
              if (event.modality != null) 'modality': event.modality,
              'payload': decode(event.payloadJson),
              if (event.rawJson != null) 'raw': decode(event.rawJson),
              if (event.binaryMimeType != null)
                'binary': {
                  'mimeType': event.binaryMimeType,
                  'byteLength': event.binaryData?.length ?? 0,
                  'encoding': 'base64',
                  'data': base64Encode(event.binaryData ?? Uint8List(0)),
                },
              'remoteSynced': event.remoteSynced,
            },
          )
          .toList(growable: false),
    });
  }

  Future<File> exportSessionFile(
    String sessionId, {
    Directory? directory,
  }) async {
    final target =
        directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'exports'),
        );
    await target.create(recursive: true);
    final file = File(p.join(target.path, 'voice-session-$sessionId.json'));
    await file.writeAsString(await exportSessionJson(sessionId), flush: true);
    return file;
  }

  /// Exports every locally retained session. This deliberately has no
  /// pagination because the resulting artifact must contain the full history.
  Future<String> exportAllSessionsJson() async {
    await flush();
    final sessions = await (db.select(
      db.voiceSessions,
    )..orderBy([(row) => OrderingTerm.asc(row.startedAt)])).get();
    final exported = <Object?>[];
    for (final session in sessions) {
      final envelope =
          jsonDecode(await exportSessionJson(session.id))
              as Map<String, dynamic>;
      exported.add({
        ...envelope['session'] as Map<String, dynamic>,
        'events': envelope['events'],
      });
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'walletbot.voice-history',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sessions': exported,
    });
  }

  Future<File> exportAllSessionsFile({Directory? directory}) async {
    final target =
        directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'exports'),
        );
    await target.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final file = File(p.join(target.path, 'voice-history-$timestamp.json'));
    await file.writeAsString(await exportAllSessionsJson(), flush: true);
    return file;
  }

  Future<void> flush() => _writeTail;

  Future<int> _takeSequence(String sessionId) async {
    final cached = _nextSequences[sessionId];
    if (cached != null) {
      _nextSequences[sessionId] = cached + 1;
      return cached;
    }
    final last =
        await (db.select(db.voiceSessionEvents)
              ..where((row) => row.sessionId.equals(sessionId))
              ..orderBy([(row) => OrderingTerm.desc(row.sequence)])
              ..limit(1))
            .getSingleOrNull();
    final next = (last?.sequence ?? -1) + 1;
    _nextSequences[sessionId] = next + 1;
    return next;
  }

  Future<BigInt> _monotonicUpdatedAt(
    String sessionId,
    DateTime occurredAt,
  ) async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final occurred = BigInt.from(occurredAt.millisecondsSinceEpoch);
    var next = occurred > now ? occurred : now;
    final session = await getSession(sessionId);
    if (session != null && session.updatedAt > next) {
      next = session.updatedAt;
    }
    return next;
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}
