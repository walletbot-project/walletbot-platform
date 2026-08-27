import 'package:app/database.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Per-chunk protocol traffic stays in the local log and out of the outbox.
/// The local log is what export reads, so nothing is lost on device; what
/// changes is that the server copy stops carrying ~92% of the rows.
void main() {
  late AppDatabase db;
  late VoiceSessionRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = VoiceSessionRepository(db, remoteEnabled: true);
  });

  tearDown(() => db.close());

  Future<void> append(String sessionId, String type) => repository.appendEvent(
    sessionId: sessionId,
    occurredAt: DateTime.now(),
    type: type,
    direction: 'local',
  );

  test('per-chunk traffic is recorded locally but never queued', () async {
    final session = await repository.openOrCreate(model: 'm');
    await append(session.id, 'audio_input_chunk');
    await append(session.id, 'server_message');
    await append(session.id, 'transcript');

    final queued = await repository.unsyncedEvents();
    expect(queued.map((e) => e.type), [
      'transcript',
    ], reason: 'only the conversation event replicates');

    final all = await db.select(db.voiceSessionEvents).get();
    expect(
      all,
      hasLength(3),
      reason: 'the local log stays complete, export depends on it',
    );
  });

  test(
    'a session whose only new rows are local-only is not re-queued',
    () async {
      // Otherwise every audio chunk still bumps the session into the outbox and
      // the drain wakes for it anyway, which is most of what it was doing.
      final session = await repository.openOrCreate(model: 'm');
      await repository.markSessionSyncedIfUnchanged(
        session.id,
        session.updatedAt,
      );
      expect(await repository.unsyncedSessions(), isEmpty);

      await append(session.id, 'audio_output_chunk');
      expect(await repository.unsyncedSessions(), isEmpty);

      await append(session.id, 'transcript');
      expect(await repository.unsyncedSessions(), hasLength(1));
    },
  );

  test('the backlog retirement clears old per-chunk rows only', () async {
    // A device upgrading into the rule still holds every per-chunk row it
    // recorded under the old one, and would drain all of them first.
    final session = await repository.openOrCreate(model: 'm');
    final legacy = VoiceSessionRepository(db, remoteEnabled: true);
    await legacy.appendEvent(
      sessionId: session.id,
      occurredAt: DateTime.now(),
      type: 'transcript',
      direction: 'local',
    );
    await db
        .update(db.voiceSessionEvents)
        .write(const VoiceSessionEventsCompanion(remoteSynced: Value(false)));
    await append(session.id, 'audio_input_chunk');
    await db
        .update(db.voiceSessionEvents)
        .write(const VoiceSessionEventsCompanion(remoteSynced: Value(false)));

    final retired = await repository.retireLocalOnlyBacklog();

    expect(retired, 1);
    expect(
      (await repository.unsyncedEvents()).map((e) => e.type),
      ['transcript'],
      reason: 'conversation rows still owe replication',
    );
  });

  test('a local account replicates nothing at all', () async {
    final local = VoiceSessionRepository(db, remoteEnabled: false);
    expect(local.replicates('transcript'), isFalse);
    expect(repository.replicates('transcript'), isTrue);
    expect(repository.replicates('audio_input_chunk'), isFalse);
  });
}
