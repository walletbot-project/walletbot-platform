import 'dart:async';
import 'dart:convert';

import 'package:app/convex/convex_client.dart';
import 'package:app/database.dart';
import 'package:app/voice/voice_session_remote_sync.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// One mutation per batch, so this is the record of how the drain carved the
/// outbox up.
class RecordingClient implements ConvexClient {
  RecordingClient({this.gate});

  final Future<void> Function()? gate;
  final List<List<String>> batches = [];
  final List<String> sessionIds = [];
  int inFlight = 0;
  int peakInFlight = 0;

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    final events = (args['events']! as List).cast<Map<String, Object?>>();
    final session = (args['session']! as Map)['id']! as String;
    batches.add(events.map((e) => e['id']! as String).toList());
    sessionIds.add(session);
    inFlight += 1;
    peakInFlight = inFlight > peakInFlight ? inFlight : peakInFlight;
    try {
      if (gate != null) await gate!();
    } finally {
      inFlight -= 1;
    }
    return null as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<VoiceSessionRepository> makeRepository(AppDatabase db) async =>
    VoiceSessionRepository(db, remoteEnabled: true);

Future<void> addEvents(
  VoiceSessionRepository repository, {
  required String sessionId,
  required int count,
  String? rawJson,
}) async {
  for (var i = 0; i < count; i++) {
    await repository.appendEvent(
      sessionId: sessionId,
      occurredAt: DateTime.now(),
      type: 'system',
      direction: 'local',
      raw: rawJson == null
          ? null
          : (jsonDecode(rawJson) as Map).cast<String, Object?>(),
    );
  }
}

void main() {
  test('a batch is one session, not a fragment of a global page', () async {
    // The drain used to read the globally oldest rows and then throw away
    // everything not belonging to the first row's session. With two sessions
    // pending that meant reading a full page and sending a slice of it.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = await makeRepository(db);

    final first = await repository.openOrCreate(model: 'm');
    await addEvents(repository, sessionId: first.id, count: 30);
    await repository.endExplicitly(first.id);
    final second = await repository.openOrCreate(model: 'm');
    await addEvents(repository, sessionId: second.id, count: 30);

    final client = RecordingClient();
    final sync = VoiceSessionRemoteSync(
      repository: repository,
      ownerId: 'owner-1',
      client: client,
    );
    addTearDown(sync.dispose);

    await sync.flush();

    final withEvents = <String, int>{};
    for (var i = 0; i < client.batches.length; i++) {
      if (client.batches[i].isEmpty) continue;
      withEvents[client.sessionIds[i]] =
          (withEvents[client.sessionIds[i]] ?? 0) + client.batches[i].length;
    }
    expect(withEvents[first.id], 30);
    expect(withEvents[second.id], 30);
    // 60 rows is one batch per session, not one batch per interleaved slice.
    expect(
      client.batches.where((b) => b.isNotEmpty).length,
      2,
      reason: 'each session went in a single batch',
    );
  });

  test('the byte budget splits a page that the row cap would not', () async {
    // rawJson carries whole protocol frames, so rows are wildly uneven in
    // size. A row count alone would put 200 of these in one mutation and blow
    // past Convex's argument limit.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = await makeRepository(db);
    final session = await repository.openOrCreate(model: 'm');

    final fat = jsonEncode({'blob': 'x' * 300000});
    await addEvents(repository, sessionId: session.id, count: 3, rawJson: fat);

    final client = RecordingClient();
    final sync = VoiceSessionRemoteSync(
      repository: repository,
      ownerId: 'owner-1',
      client: client,
    );
    addTearDown(sync.dispose);

    await sync.flush();

    final eventBatches = client.batches.where((b) => b.isNotEmpty).toList();
    expect(eventBatches, hasLength(3), reason: 'one fat row per mutation');
    expect(eventBatches.every((b) => b.length == 1), isTrue);
  });

  test('batches after the first go out concurrently', () async {
    // The first carries the session payload into a document the server may
    // still have to write. The rest find it unchanged, so they no longer
    // conflict and can overlap.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = await makeRepository(db);
    final session = await repository.openOrCreate(model: 'm');

    final fat = jsonEncode({'blob': 'x' * 300000});
    await addEvents(repository, sessionId: session.id, count: 5, rawJson: fat);

    final release = Completer<void>();
    final client = RecordingClient(gate: () => release.future);
    final sync = VoiceSessionRemoteSync(
      repository: repository,
      ownerId: 'owner-1',
      client: client,
    );
    addTearDown(sync.dispose);

    final drain = sync.flush();
    await pumpUntil(() => client.peakInFlight > 1 || client.inFlight == 1);
    release.complete();
    await drain;

    expect(client.batches.where((b) => b.isNotEmpty), hasLength(5));
    expect(
      client.peakInFlight,
      greaterThan(1),
      reason: 'the tail batches overlapped instead of running one by one',
    );
  });

  test('a pass takes a bite of a large backlog and reschedules', () async {
    // The outbox is a backlog, not a deadline. Draining all of it in one go
    // is what put a long run of mutations on the radio mid-conversation.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = await makeRepository(db);
    final session = await repository.openOrCreate(model: 'm');

    final fat = jsonEncode({'blob': 'x' * 300000});
    await addEvents(repository, sessionId: session.id, count: 12, rawJson: fat);

    final client = RecordingClient();
    final sync = VoiceSessionRemoteSync(
      repository: repository,
      ownerId: 'owner-1',
      client: client,
    );
    addTearDown(sync.dispose);

    await sync.flush();

    expect(
      client.batches.where((b) => b.isNotEmpty),
      hasLength(8),
      reason: 'capped at 8 batches per pass, with 4 rows left for the retry',
    );
    expect(await repository.hasUnsyncedEvents(session.id), isTrue);
  });
}

Future<void> pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition never became true');
}
