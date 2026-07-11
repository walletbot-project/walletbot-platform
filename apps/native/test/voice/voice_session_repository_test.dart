import 'dart:convert';
import 'dart:typed_data';

import 'package:app/database.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'exports ordered, timestamped semantic events and lossless PCM',
    () async {
      final repository = VoiceSessionRepository(db);
      final session = await repository.openOrCreate(model: 'test-live-model');
      final firstAt = DateTime.utc(2026, 7, 11, 12, 0, 0, 100);
      final secondAt = firstAt.add(const Duration(milliseconds: 25));

      await repository.appendEvent(
        sessionId: session.id,
        occurredAt: firstAt,
        type: 'mute_changed',
        direction: 'client',
        modality: 'voice',
        payload: const {'muted': true, 'reason': 'tap_mute'},
      );
      await repository.appendEvent(
        sessionId: session.id,
        occurredAt: secondAt,
        type: 'audio_input_chunk',
        direction: 'client',
        modality: 'audio',
        payload: const {'byteLength': 4},
        raw: const {
          'realtimeInput': {
            'audio': {'data': '<stored in binary event>'},
          },
        },
        binaryData: Uint8List.fromList([0, 1, 2, 255]),
        binaryMimeType: 'audio/pcm;rate=16000',
      );

      final export = jsonDecode(await repository.exportSessionJson(session.id));
      expect(export['format'], 'walletbot.voice-session');
      expect(export['version'], 1);
      expect(export['session']['model'], 'test-live-model');
      final events = export['events'] as List<dynamic>;
      expect(events, hasLength(2));
      expect(events[0]['sequence'], 0);
      expect(events[0]['occurredAt'], firstAt.toIso8601String());
      expect(events[0]['payload']['reason'], 'tap_mute');
      expect(events[1]['sequence'], 1);
      expect(events[1]['occurredAt'], secondAt.toIso8601String());
      expect(events[1]['binary']['mimeType'], 'audio/pcm;rate=16000');
      expect(events[1]['binary']['data'], base64Encode([0, 1, 2, 255]));
      expect(events[1]['raw']['realtimeInput'], isNotNull);

      final history = jsonDecode(await repository.exportAllSessionsJson());
      expect(history['format'], 'walletbot.voice-history');
      expect(history['sessions'], hasLength(1));
      expect(history['sessions'][0]['events'], hasLength(2));
    },
  );

  test('reuses a resumable open session and explicit end closes it', () async {
    final repository = VoiceSessionRepository(db);
    final original = await repository.openOrCreate(model: 'test-live-model');
    await repository.updateResumeHandle(
      sessionId: original.id,
      handle: 'resume-handle',
      at: DateTime.now(),
    );

    final resumed = await repository.openOrCreate(model: 'test-live-model');
    expect(resumed.id, original.id);
    expect(resumed.resumeHandle, 'resume-handle');

    await repository.endExplicitly(original.id);
    final ended = await repository.getSession(original.id);
    expect(ended?.status, 'ended');
    expect(ended?.endedExplicitly, isTrue);

    final next = await repository.openOrCreate(model: 'test-live-model');
    expect(next.id, isNot(original.id));
  });

  test('remote sessions use an outbox while local sessions do not', () async {
    final remote = VoiceSessionRepository(db, remoteEnabled: true);
    final session = await remote.openOrCreate(model: 'test-live-model');
    expect(await remote.unsyncedSessions(), [session]);
    await remote.appendEvent(
      sessionId: session.id,
      occurredAt: DateTime.now(),
      type: 'send_message',
      direction: 'client',
      modality: 'text',
      payload: const {'text': 'hola'},
    );
    expect(await remote.unsyncedEvents(), hasLength(1));
  });

  test('backdated events do not move session updatedAt backwards', () async {
    final repository = VoiceSessionRepository(db);
    final session = await repository.openOrCreate(model: 'test-live-model');

    await repository.appendEvent(
      sessionId: session.id,
      occurredAt: DateTime.utc(2000),
      type: 'historical_event',
      direction: 'local',
    );

    final updated = await repository.getSession(session.id);
    expect(updated, isNotNull);
    expect(
      updated!.updatedAt.compareTo(session.updatedAt),
      greaterThanOrEqualTo(0),
    );
  });

  test(
    'resume and expiration changes return remote sessions to outbox',
    () async {
      final repository = VoiceSessionRepository(db, remoteEnabled: true);
      final resumable = await repository.openOrCreate(model: 'test-live-model');
      await repository.updateResumeHandle(
        sessionId: resumable.id,
        handle: 'fresh-handle',
        at: DateTime.now(),
      );
      final fresh = await repository.getSession(resumable.id);
      await repository.markSessionSyncedIfUnchanged(
        resumable.id,
        fresh!.updatedAt,
      );

      final resumed = await repository.openOrCreate(model: 'test-live-model');
      expect(resumed.id, resumable.id);
      expect(resumed.remoteSynced, isFalse);

      await repository.updateResumeHandle(
        sessionId: resumed.id,
        handle: 'expired-handle',
        at: DateTime.now().subtract(const Duration(hours: 3)),
      );
      final stale = await repository.getSession(resumed.id);
      await repository.markSessionSyncedIfUnchanged(
        resumed.id,
        stale!.updatedAt,
      );

      final replacement = await repository.openOrCreate(
        model: 'test-live-model',
      );
      final expired = await repository.getSession(resumed.id);
      expect(replacement.id, isNot(resumed.id));
      expect(expired?.status, 'expired');
      expect(expired?.remoteSynced, isFalse);
      expect(
        (await repository.unsyncedSessions()).map((session) => session.id),
        containsAll([expired!.id, replacement.id]),
      );
    },
  );

  test('stale sync acknowledgement preserves a newer session update', () async {
    final repository = VoiceSessionRepository(db, remoteEnabled: true);
    final original = await repository.openOrCreate(model: 'test-live-model');

    await repository.markStatus(original.id, 'connecting');
    final snapshot = await repository.getSession(original.id);
    expect(snapshot, isNotNull);

    await repository.markStatus(original.id, 'active');
    expect(
      await repository.markSessionSyncedIfUnchanged(
        original.id,
        snapshot!.updatedAt,
      ),
      isFalse,
    );

    final current = await repository.getSession(original.id);
    expect(current?.status, 'active');
    expect(current?.remoteSynced, isFalse);
    expect(current!.updatedAt, greaterThan(snapshot.updatedAt));
  });
}
