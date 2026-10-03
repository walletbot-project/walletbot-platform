import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/values.dart';
import 'package:app/database.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../convex/helpers/fake_convex_server.dart';
import '../generated_migrations/schema.dart';

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Expected protocol message or completed cycle',
  );
}

void main() {
  test(
    'real sync engine hydrates web position after v5 upgrade with offline rename',
    () async {
      final schema = await SchemaVerifier(GeneratedHelper()).schemaAt(5);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        "INSERT INTO accounts (id, name, currency, created_at, updated_at, dirty) VALUES ('a', 'Offline rename', 'ARS', 1, 200, 1)",
      );
      schema.rawDatabase.execute(
        "INSERT INTO sync_state (id, last_server_seq) VALUES ('singleton', 5)",
      );
      final db = AppDatabase.forTesting(schema.newConnection());
      final server = FakeConvexServer();
      final client = ConvexClient(
        ConvexClientConfig(
          deploymentUrl: 'https://example.convex.cloud',
          clientId: 'ordering-upgrade-test',
        ),
        socketFactory: server.connect,
        random: FixedRandom(),
        sessionId: 'ordering-upgrade-test',
      );
      final engine = SyncEngine(
        db: db,
        client: client,
        clientInfo: const ClientInfo(
          platform: 'android',
          appVersion: '0.5.1',
          deviceId: 'ordering-upgrade-test',
        ),
      );
      addTearDown(() async {
        engine.dispose();
        await client.dispose();
        await db.close();
      });
      await engine.start();
      await _until(
        () =>
            server.connections.isNotEmpty &&
            server.latest
                .ofType('ModifyQuerySet')
                .any(
                  (q) => (q['modifications'] as List).any(
                    (m) => m['udfPath'] == 'v1/sync/queries:pull',
                  ),
                ),
      );
      final conn = server.latest;
      final sets = conn.ofType('ModifyQuerySet');
      final adds = sets
          .expand(
            (q) => (q['modifications'] as List).cast<Map<String, Object?>>(),
          )
          .where((m) => m['type'] == 'Add')
          .toList();
      conn.transition(
        toQuerySet: sets.last['newVersion'] as int,
        modifications: [
          for (final add in adds)
            {
              'type': 'QueryUpdated',
              'queryId': add['queryId'],
              'value': convexToJson(
                add['udfPath'] == 'v1/sync/queries:getCounter'
                    ? BigInt.from(10)
                    : {
                        'rows': [
                          {
                            'tableName': 'accounts',
                            'row': {
                              'id': 'a',
                              'name': 'Before rename',
                              'currency': 'ARS',
                              'color': '#000000',
                              'icon': 'wallet',
                              'createdAt': BigInt.one,
                              'updatedAt': BigInt.from(100),
                              'isArchived': false,
                              'position': 0.0,
                            },
                          },
                        ],
                        'tombstones': [],
                        'hasMore': false,
                        'currentCounter': BigInt.from(10),
                      },
              ),
              'logLines': <String>[],
              'journal': null,
            },
        ],
      );
      await _until(() => conn.ofType('Mutation').isNotEmpty);
      final mutation = conn.ofType('Mutation').single;
      final args = (mutation['args'] as List).single as Map;
      final account =
          ((args['upserts'] as Map)['accounts'] as List).single as Map;
      expect(account['position'], 0);
      conn.respondToMutation(mutation['requestId'] as int, {
        'ok': true,
        'newSeq': convexToJson(BigInt.from(11)),
      }, ts: 11);
      conn.transition(toTs: 11);
      await _until(() => engine.lastSyncedAt != null);
      final saved = await db.select(db.accounts).getSingle();
      final cursor = await db.select(db.syncState).getSingle();
      expect(saved.name, 'Offline rename');
      expect(saved.dirty, isFalse);
      expect(cursor.lastServerSeq, BigInt.from(11));
      expect(
        saved.position,
        0,
        reason: 'The completed sync must retain the hydrated server position',
      );
    },
  );
}
