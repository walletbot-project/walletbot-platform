import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/database.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/sync/sync_status.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../convex/helpers/fake_convex_server.dart';

/// A failed sync cycle used to be terminal: `SyncStatus.error` with nothing
/// scheduled to clear it. The only triggers left were a local write, a server
/// counter that *advanced*, and tapping the pill — so coming back from
/// airplane mode with nothing changed remotely stayed broken until the user
/// edited something. These cover the two recovery paths that fix it.
void main() {
  const clientInfo = ClientInfo(
    platform: 'ios',
    appVersion: '1.0.0',
    deviceId: 'device-1',
  );

  late AppDatabase db;
  late FakeConvexServer server;
  late ConvexClient client;
  late SyncEngine engine;
  late Set<int> answered;
  late bool engineDisposed;

  setUp(() {
    answered = {};
    engineDisposed = false;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = FakeConvexServer();
    client = ConvexClient(
      ConvexClientConfig(
        deploymentUrl: 'https://example.convex.cloud',
        clientId: 'test',
        initialBackoff: const Duration(milliseconds: 10),
        maxBackoff: const Duration(milliseconds: 20),
      ),
      socketFactory: server.connect,
      random: FixedRandom(),
      sessionId: 'session-1',
    );
    engine = SyncEngine(
      db: db,
      client: client,
      clientInfo: clientInfo,
      retryFloor: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    if (!engineDisposed) engine.dispose();
    await client.dispose();
    await db.close();
  });

  void disposeEngine() {
    engine.dispose();
    engineDisposed = true;
  }

  /// Answers every not-yet-answered `pull` subscription with a body the merger
  /// rejects, the cheapest deterministic way to fail a cycle. Returns how many
  /// new cycles it just failed.
  int failNewPulls() {
    final connection = server.latest;
    final querySets = connection.ofType('ModifyQuerySet');
    final adds = querySets
        .expand(
          (m) => (m['modifications']! as List).cast<Map<String, Object?>>(),
        )
        .where(
          (m) => m['type'] == 'Add' && m['udfPath'] == 'v1/sync/queries:pull',
        )
        .where((m) => answered.add(m['queryId']! as int))
        .toList();
    if (adds.isEmpty) return 0;
    final target = querySets
        .map((m) => m['newVersion']! as int)
        .reduce((a, b) => a > b ? a : b);
    connection.transition(
      toQuerySet: target,
      modifications: [
        for (final add in adds)
          {
            'type': 'QueryUpdated',
            'queryId': add['queryId'],
            'value': null,
            'logLines': <String>[],
            'journal': null,
          },
      ],
    );
    return adds.length;
  }

  Future<void> settle() => pumpEventQueue(times: 40);

  Future<void> wait(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await settle();
  }

  test(
    'a failed cycle retries on its own instead of parking in error',
    () async {
      await engine.start();
      await settle();
      expect(failNewPulls(), 1, reason: 'the first cycle ran');
      await settle();
      expect(engine.status, SyncStatus.error);

      // Nothing changed server-side and nothing was written locally. This is
      // where the engine used to stop forever.
      await wait(80);
      expect(
        failNewPulls(),
        greaterThan(0),
        reason: 'the engine scheduled another cycle by itself',
      );
    },
  );

  test('the retry backs off instead of hammering', () async {
    await engine.start();
    await settle();
    var cycles = failNewPulls();
    await settle();

    // Floor is 20 ms doubling per failure, so ~300 ms buys a handful of
    // attempts, not hundreds.
    for (var i = 0; i < 6; i++) {
      await wait(50);
      cycles += failNewPulls();
      await settle();
    }
    expect(cycles, greaterThan(1));
    expect(cycles, lessThan(15), reason: 'backoff, not a hot loop');
  });

  test(
    'a reconnect triggers a cycle even when the counter did not move',
    () async {
      await engine.start();
      await settle();
      failNewPulls();
      await settle();
      expect(engine.status, SyncStatus.error);

      // Drop and restore the socket. The counter subscription re-delivers the
      // same value on the new socket, so it schedules nothing on its own.
      server.latest.serverClose();
      await settle();
      await wait(60);

      expect(client.currentConnectionState.status, ConnectionStatus.ready);
      expect(
        failNewPulls(),
        greaterThan(0),
        reason: 'the reconnect re-ran the cycle',
      );
    },
  );

  test('dispose stops the retry timer', () async {
    await engine.start();
    await settle();
    failNewPulls();
    await settle();
    expect(engine.status, SyncStatus.error);

    disposeEngine();
    await wait(200);
    expect(failNewPulls(), 0, reason: 'no further cycles after dispose');
  });
}
