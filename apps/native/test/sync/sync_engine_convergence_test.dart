import 'dart:convert';

import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/values.dart';
import 'package:app/database.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/sync/sync_status.dart';
import 'package:app/telemetry/telemetry_client.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../convex/helpers/fake_convex_server.dart';

/// How the scripted backend answers one `v1/sync/mutations:push`.
enum _PushReply {
  /// `{ok: true, newSeq}` — the batch committed.
  ok,

  /// `{ok: false, error: 'cursor_mismatch', currentCounter}` — another writer
  /// advanced the counter; returned as data.
  cursorMismatch,

  /// `{ok: false, error: 'push_failed'}` — the batch threw server-side and the
  /// backend returned it as data (it records the error itself).
  pushFailed,

  /// The mutation throws `Unauthenticated` (`requireAuth`), so the client
  /// sees a [ConvexFunctionError].
  throwUnauthenticated,

  /// The mutation throws something else.
  throwOther,

  /// Never answered: the client's operation timeout fires.
  hang,
}

/// A minimal stand-in for the sync backend on top of [FakeConvexServer]:
/// answers every `pull` with an empty page at the current server counter and
/// answers each `push` with the next scripted [_PushReply]. A push that
/// arrives while the script is empty is held until a reply is queued, so a
/// test can stop the engine at a precise point.
class _SyncBackend {
  _SyncBackend(this.server, {required this.counter});

  final FakeConvexServer server;
  BigInt counter;
  final List<_PushReply> replies = [];

  /// `pull` / `push` in the order the client sent them.
  final List<String> calls = [];

  /// `since` of every pull and `expectedServerSeq` of every push, in order.
  final List<BigInt> pullSince = [];
  final List<BigInt> pushExpected = [];

  int pushesAnswered = 0;

  final List<Map<String, Object?>> _heldPushes = [];
  FakeConnection? _connection;
  int _processed = 0;
  int _ts = 0;

  void pump() {
    if (server.connections.isEmpty) return;
    final connection = server.latest;
    if (!identical(connection, _connection)) {
      _connection = connection;
      _processed = 0;
    }
    while (_processed < connection.received.length) {
      final message = connection.received[_processed++];
      switch (message['type']) {
        case 'ModifyQuerySet':
          _answerPulls(connection, message);
        case 'Mutation' when message['udfPath'] == 'v1/sync/mutations:push':
          calls.add('push');
          final args = (message['args']! as List).single as Map;
          pushExpected.add(jsonToConvex(args['expectedServerSeq']) as BigInt);
          _heldPushes.add(message);
      }
    }
    while (_heldPushes.isNotEmpty && replies.isNotEmpty) {
      _answerPush(connection, _heldPushes.removeAt(0), replies.removeAt(0));
    }
  }

  void _answerPulls(FakeConnection connection, Map<String, Object?> message) {
    final pulls = (message['modifications']! as List)
        .cast<Map<String, Object?>>()
        .where(
          (m) => m['type'] == 'Add' && m['udfPath'] == 'v1/sync/queries:pull',
        )
        .toList();
    if (pulls.isEmpty) return;
    for (final pull in pulls) {
      calls.add('pull');
      final args = (pull['args']! as List).single as Map;
      pullSince.add(jsonToConvex(args['since']) as BigInt);
    }
    connection.transition(
      toQuerySet: message['newVersion']! as int,
      modifications: [
        for (final pull in pulls)
          {
            'type': 'QueryUpdated',
            'queryId': pull['queryId'],
            'value': convexToJson({
              'rows': <Object?>[],
              'tombstones': <Object?>[],
              'hasMore': false,
              'currentCounter': counter,
            }),
            'logLines': <String>[],
            'journal': null,
          },
      ],
    );
  }

  void _answerPush(
    FakeConnection connection,
    Map<String, Object?> message,
    _PushReply reply,
  ) {
    pushesAnswered += 1;
    final requestId = message['requestId']! as int;
    void respond(Map<String, Object?> result) {
      _ts += 1;
      connection.respondToMutation(requestId, convexToJson(result), ts: _ts);
      // A mutation's Future resolves once a Transition reaches its commit ts.
      connection.transition(toTs: _ts);
    }

    switch (reply) {
      case _PushReply.ok:
        counter += BigInt.one;
        respond({'ok': true, 'newSeq': counter});
      case _PushReply.cursorMismatch:
        counter += BigInt.one;
        respond({
          'ok': false,
          'error': 'cursor_mismatch',
          'currentCounter': counter,
        });
      case _PushReply.pushFailed:
        respond({'ok': false, 'error': 'push_failed'});
      case _PushReply.throwUnauthenticated:
        connection.failMutation(requestId, 'Unauthenticated');
      case _PushReply.throwOther:
        connection.failMutation(requestId, 'Server Error');
      case _PushReply.hang:
        break;
    }
  }
}

void main() {
  const clientInfo = ClientInfo(
    platform: 'ios',
    appVersion: '1.0.0',
    deviceId: 'device-1',
  );

  late AppDatabase db;
  late FakeConvexServer server;
  late _SyncBackend backend;
  late ConvexClient client;
  late SyncEngine engine;
  late TelemetryClient telemetry;
  late List<Map<String, Object?>> metrics;
  late List<SyncStatus> statuses;

  Future<void> build({
    Duration operationTimeout = const Duration(seconds: 30),
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    metrics = [];
    statuses = [];
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            id: const Value('singleton'),
            lastServerSeq: Value(BigInt.from(5)),
          ),
        );
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'a1',
            name: 'Offline account',
            currency: 'ARS',
            createdAt: BigInt.one,
            updatedAt: BigInt.from(100),
            dirty: const Value(true),
          ),
        );
    server = FakeConvexServer();
    backend = _SyncBackend(server, counter: BigInt.from(5));
    client = ConvexClient(
      ConvexClientConfig(
        deploymentUrl: 'https://example.convex.cloud',
        clientId: 'convergence-test',
        initialBackoff: const Duration(milliseconds: 10),
        maxBackoff: const Duration(milliseconds: 20),
        defaultOperationTimeout: operationTimeout,
      ),
      socketFactory: server.connect,
      random: FixedRandom(),
      sessionId: 'session-1',
    );
    telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        metrics.addAll((body['metrics']! as List).cast<Map<String, Object?>>());
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );
    engine = SyncEngine(
      db: db,
      client: client,
      clientInfo: clientInfo,
      telemetryClient: telemetry,
      retryFloor: const Duration(milliseconds: 20),
    );
    engine.addListener(() => statuses.add(engine.status));
    addTearDown(() async {
      engine.dispose();
      await client.dispose();
      telemetry.dispose();
      await db.close();
    });
  }

  /// Answers whatever the engine sent, repeatedly, until [condition] holds.
  Future<void> driveUntil(bool Function() condition, {String? reason}) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      backend.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<Account> account() =>
      (db.select(db.accounts)..where((a) => a.id.equals('a1'))).getSingle();

  Future<BigInt> lastServerSeq() async =>
      (await db.select(db.syncState).getSingle()).lastServerSeq;

  List<Map<String, Object?>> metricsNamed(String name) =>
      metrics.where((m) => m['name'] == name).toList();

  Future<void> expectConverged({required BigInt seq}) async {
    expect(engine.status, SyncStatus.synced);
    expect((await account()).dirty, isFalse);
    expect(await lastServerSeq(), seq);
  }

  test(
    'cursor_mismatch drains pull again, then the retried push converges',
    () async {
      await build();
      backend.replies.addAll([_PushReply.cursorMismatch, _PushReply.ok]);
      await engine.start();

      await driveUntil(
        () => backend.pushesAnswered == 2 && engine.status == SyncStatus.synced,
      );

      expect(backend.calls.take(4), [
        'pull',
        'push',
        'pull',
        'push',
      ], reason: 'the mismatch re-ran the pull before the retried push');
      // First round: cursor 5. The mismatch moved the server to 6, the re-pull
      // adopted it, and the retry was sent against 6.
      expect(backend.pullSince.take(2), [BigInt.from(5), BigInt.from(5)]);
      expect(backend.pushExpected, [BigInt.from(5), BigInt.from(6)]);
      // The retry committed as seq 7.
      await expectConverged(seq: BigInt.from(7));
      expect(statuses, isNot(contains(SyncStatus.error)));
    },
  );

  test(
    'a push_failed returned as data errors, retries on its own and converges '
    'without a client-side push failure',
    () async {
      await build();
      backend.replies.add(_PushReply.pushFailed);
      await engine.start();

      await driveUntil(() => engine.status == SyncStatus.error);
      expect((await account()).dirty, isTrue, reason: 'nothing was acked');
      expect(await lastServerSeq(), BigInt.from(5));

      // No local write, no counter change: only the retry timer can run the
      // next cycle.
      backend.replies.add(_PushReply.ok);
      await driveUntil(
        () => backend.pushesAnswered == 2 && engine.status == SyncStatus.synced,
      );
      await expectConverged(seq: BigInt.from(6));

      // The backend records a returned push_failed itself.
      expect(metricsNamed('sync.push.client_failures.count'), isEmpty);
    },
  );

  for (final (reply, reason) in [
    (_PushReply.throwUnauthenticated, 'auth_failure'),
    (_PushReply.throwOther, 'unknown'),
  ]) {
    test('a thrown push ($reason) is recorded once on the client and the retry '
        'converges', () async {
      await build();
      backend.replies.add(reply);
      await engine.start();

      await driveUntil(() => engine.status == SyncStatus.error);
      await driveUntil(
        () => metricsNamed('sync.push.client_failures.count').isNotEmpty,
        reason: 'the telemetry send is best effort, not awaited',
      );
      expect((await account()).dirty, isTrue);

      backend.replies.add(_PushReply.ok);
      await driveUntil(
        () => backend.pushesAnswered == 2 && engine.status == SyncStatus.synced,
      );
      await expectConverged(seq: BigInt.from(6));

      final failures = metricsNamed('sync.push.client_failures.count');
      expect(failures, hasLength(1));
      final failure = failures.single;
      expect(failure['type'], 'counter');
      expect(failure['unit'], 'count');
      expect(failure['value'], 1);
      expect(failure['attributes'], {
        'reason': reason,
        'platform': currentPlatform,
      });
    });
  }

  test('a push that times out is recorded as a network failure', () async {
    await build(operationTimeout: const Duration(milliseconds: 100));
    backend.replies.add(_PushReply.hang);
    await engine.start();

    await driveUntil(() => engine.status == SyncStatus.error);
    await driveUntil(
      () => metricsNamed('sync.push.client_failures.count').isNotEmpty,
    );

    backend.replies.add(_PushReply.ok);
    await driveUntil(
      () => backend.pushesAnswered == 2 && engine.status == SyncStatus.synced,
    );
    await expectConverged(seq: BigInt.from(6));

    final failures = metricsNamed('sync.push.client_failures.count');
    expect(failures, hasLength(1));
    expect(failures.single['attributes'], {
      'reason': 'network',
      'platform': currentPlatform,
    });
  });

  test('CURRENT BEHAVIOUR: after 5 cursor_mismatch rounds the cycle reports '
      'synced with rows still dirty; the next trigger pushes them', () async {
    await build();
    backend.replies.addAll(List.filled(5, _PushReply.cursorMismatch));
    await engine.start();

    await driveUntil(
      () =>
          backend.pushesAnswered == 5 &&
          statuses.isNotEmpty &&
          statuses.last == SyncStatus.synced,
    );

    expect(backend.calls.take(10), [
      for (var i = 0; i < 5; i++) ...['pull', 'push'],
    ]);
    // Pinned as-is (`_runOnce` gives up after 5 rounds and falls through
    // to the success path): nothing was pushed, yet the status is synced.
    expect(engine.status, SyncStatus.synced);
    expect((await account()).dirty, isTrue);
    expect(engine.lastSyncedAt, isNotNull);
    expect(statuses, isNot(contains(SyncStatus.error)));
    expect(metricsNamed('sync.push.client_failures.count'), isEmpty);

    backend.replies.add(_PushReply.ok);
    final cycle = engine.sync();
    await driveUntil(
      () => backend.pushesAnswered == 6 && engine.status == SyncStatus.synced,
    );
    await cycle;
    // 5 mismatches moved the counter 5 → 10; the push committed as 11.
    expect(backend.pushExpected.last, BigInt.from(10));
    await expectConverged(seq: BigInt.from(11));
  });
}
