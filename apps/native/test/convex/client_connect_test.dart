import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/protocol.dart';
import 'package:app/convex/values.dart';

import 'helpers/fake_convex_server.dart';

void main() {
  test('connects, sends Connect first, and reaches ready', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      expect(h.server.connectAttempts, 1);
      expect(h.server.lastHeaders?['Convex-Client'], 'dart-test-0.0.0');
      final conn = h.server.latest;
      expect(conn.receivedTypes, ['Connect']);
      final connect = conn.received.single;
      expect(connect['sessionId'], 'session-1');
      expect(connect['connectionCount'], 1);
      expect(connect['lastCloseReason'], 'InitialConnect');
      expect(connect.containsKey('maxObservedTimestamp'), isFalse);
      expect(connect['clientTs'], isA<int>());
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('subscribe sends Add and delivers typed updates', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final updates = <Object?>[];
      final errors = <ConvexFunctionError>[];
      h.client.subscribe(
        'v1/sync/queries:getCounter',
        {},
        onUpdate: updates.add,
        onError: errors.add,
      );
      fake.flushMicrotasks();
      final modify = conn.ofType('ModifyQuerySet').single;
      expect(modify['baseVersion'], 0);
      expect(modify['newVersion'], 1);
      final add = ((modify['modifications'] as List).single as Map)
          .cast<String, Object?>();
      expect(add['type'], 'Add');
      expect(add['queryId'], 0);
      expect(add['udfPath'], 'v1/sync/queries:getCounter');
      expect(add['args'], [<String, Object?>{}]);
      expect(add.containsKey('journal'), isFalse);

      conn.transition(
        toQuerySet: 1,
        toTs: 10,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': convexToJson(BigInt.from(42)),
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(updates, [BigInt.from(42)]);
      expect(errors, isEmpty);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('query failure delivers ConvexFunctionError with decoded errorData', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final errors = <ConvexFunctionError>[];
      h.client.subscribe(
        'v1/users/queries:getSettings',
        {},
        onUpdate: (_) => fail('should not update'),
        onError: errors.add,
      );
      fake.flushMicrotasks();
      conn.transition(
        toQuerySet: 1,
        toTs: 5,
        modifications: [
          {
            'type': 'QueryFailed',
            'queryId': 0,
            'errorMessage': 'Uncaught ConvexError',
            'errorData': {'code': convexToJson(BigInt.from(7))},
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(errors, hasLength(1));
      expect(errors.single.errorMessage, 'Uncaught ConvexError');
      expect(errors.single.errorData, {'code': BigInt.from(7)});
      expect(errors.single.functionName, 'v1/users/queries:getSettings');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('identical subscriptions share one queryId; late subscriber gets '
      'the cached value; Remove sent after the last cancel', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final first = <Object?>[];
      final second = <Object?>[];
      final handle1 = h.client.subscribe(
        'q:f',
        {'a': 1},
        onUpdate: first.add,
        onError: (_) {},
      );
      fake.flushMicrotasks();
      conn.transition(
        toQuerySet: 1,
        toTs: 3,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': 'cached',
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      final handle2 = h.client.subscribe(
        'q:f',
        {'a': 1},
        onUpdate: second.add,
        onError: (_) {},
      );
      fake.flushMicrotasks();
      expect(conn.ofType('ModifyQuerySet'), hasLength(1));
      expect(first, ['cached']);
      expect(second, ['cached']);

      handle1.cancel();
      fake.flushMicrotasks();
      expect(conn.ofType('ModifyQuerySet'), hasLength(1));
      handle2.cancel();
      fake.flushMicrotasks();
      final removal = conn.ofType('ModifyQuerySet').last;
      expect(removal['baseVersion'], 1);
      expect(removal['newVersion'], 2);
      expect(
        ((removal['modifications'] as List).single as Map)['type'],
        'Remove',
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('one-shot query resolves on the first value and unsubscribes', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(h.client.query<BigInt>('q:count', {}));
      fake.flushMicrotasks();
      conn.transition(
        toQuerySet: 1,
        toTs: 4,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': convexToJson(BigInt.two),
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.value, BigInt.two);
      final removal = conn.ofType('ModifyQuerySet').last;
      expect(
        ((removal['modifications'] as List).single as Map)['type'],
        'Remove',
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('one-shot query rejects on a failed result', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(h.client.query<Object?>('q:bad', {}));
      fake.flushMicrotasks();
      conn.transition(
        toQuerySet: 1,
        toTs: 4,
        modifications: [
          {
            'type': 'QueryFailed',
            'queryId': 0,
            'errorMessage': 'nope',
            'errorData': null,
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.error, isA<ConvexFunctionError>());
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('restart sequence order: Connect, Authenticate, ModifyQuerySet, '
      'Mutation resends', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      h.client.setAuth(
        fetchToken: ({required bool forceRefresh}) async => makeJwt(),
      );
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth(); // confirms the fresh-token upgrade
      fake.flushMicrotasks();
      h.client.subscribe('q:f', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();
      expect(probe.isDone, isFalse);

      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      expect(h.server.connections, hasLength(2));
      conn = h.server.latest;
      expect(conn.receivedTypes, [
        'Connect',
        'Authenticate',
        'ModifyQuerySet',
        'Mutation',
      ]);
      final connect = conn.ofType('Connect').single;
      expect(connect['sessionId'], 'session-1');
      expect(connect['connectionCount'], 2);
      expect(connect['lastCloseReason'], 'closed-1000');
      final authenticate = conn.ofType('Authenticate').single;
      expect(authenticate['tokenType'], 'User');
      expect(authenticate['baseVersion'], 0);
      final modify = conn.ofType('ModifyQuerySet').single;
      expect(modify['baseVersion'], 0);
      expect(modify['newVersion'], 1);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('maxObservedTimestamp from transitions is sent on the next Connect', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      conn.transition(toTs: 77);
      fake.flushMicrotasks();
      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      expect(
        conn.ofType('Connect').single['maxObservedTimestamp'],
        encodeTs(BigInt.from(77)),
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a subscribe landing mid-restart (during the token fetch) produces '
      'consistent querySet versions', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      var gate = Completer<String?>();
      var fetches = 0;
      h.client.setAuth(
        fetchToken: ({required bool forceRefresh}) {
          fetches++;
          // The first (setAuth-time) fetch resolves immediately; restart
          // fetches go through the gate.
          if (fetches == 1) return Future.value(makeJwt());
          return gate.future;
        },
      );
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      h.client.subscribe('q:one', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();

      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      // The restart is now parked on the token fetch.
      expect(h.server.connections, hasLength(2));
      conn = h.server.latest;
      expect(conn.receivedTypes, ['Connect']);

      h.client.subscribe('q:two', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();
      expect(conn.receivedTypes, ['Connect']);

      gate.complete(makeJwt());
      fake.flushMicrotasks();
      expect(conn.receivedTypes, [
        'Connect',
        'Authenticate',
        'ModifyQuerySet',
        'ModifyQuerySet',
      ]);
      final restartModify = conn.ofType('ModifyQuerySet')[0];
      expect(restartModify['baseVersion'], 0);
      expect(restartModify['newVersion'], 1);
      final adds = (restartModify['modifications'] as List)
          .map((m) => ((m as Map)['udfPath']) as String)
          .toList();
      expect(adds, ['q:one']);
      final lateModify = conn.ofType('ModifyQuerySet')[1];
      expect(lateModify['baseVersion'], 1);
      expect(lateModify['newVersion'], 2);
      expect(
        ((lateModify['modifications'] as List).single as Map)['udfPath'],
        'q:two',
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('journals are echoed back on restart re-adds', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      h.client.subscribe('q:paginated', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();
      conn.transition(
        toQuerySet: 1,
        toTs: 2,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': 1,
            'logLines': <String>[],
            'journal': 'cursor-abc',
          },
        ],
      );
      fake.flushMicrotasks();
      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      final add =
          ((conn.ofType('ModifyQuerySet').single['modifications'] as List)
                      .single
                  as Map)
              .cast<String, Object?>();
      expect(add['journal'], 'cursor-abc');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
