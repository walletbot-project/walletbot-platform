import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/values.dart';

import 'helpers/fake_convex_server.dart';

void main() {
  test('mutation resolves only when a transition reaches the commit ts '
      '(read-your-own-writes)', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(
        h.client.mutation<Object?>('v1/sync/mutations:push', {
          'expectedServerSeq': BigInt.from(9),
        }),
      );
      fake.flushMicrotasks();
      final mutation = conn.ofType('Mutation').single;
      expect(mutation['requestId'], 0);
      expect(mutation['udfPath'], 'v1/sync/mutations:push');
      expect(mutation['args'], [
        {'expectedServerSeq': convexToJson(BigInt.from(9))},
      ]);

      conn.respondToMutation(0, {'applied': true}, ts: 100);
      fake.flushMicrotasks();
      expect(probe.isDone, isFalse);
      conn.transition(toTs: 50);
      fake.flushMicrotasks();
      expect(probe.isDone, isFalse);
      conn.transition(toTs: 120);
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.value, {'applied': true});
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('mutation failure resolves immediately with decoded errorData', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();
      conn.failMutation(
        0,
        'Uncaught Error: conflict',
        errorData: {'expected': convexToJson(BigInt.from(3))},
      );
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      final error = probe.error as ConvexFunctionError;
      expect(error.errorMessage, 'Uncaught Error: conflict');
      expect(error.errorData, {'expected': BigInt.from(3)});
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('in-flight mutation is resent on reconnect with the same requestId; '
      'duplicate responses cause exactly one resolution', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      var resolutions = 0;
      final probe = FutureProbe(
        h.client.mutation<Object?>('m:f', {}).then((v) {
          resolutions++;
          return v;
        }),
      );
      fake.flushMicrotasks();
      expect(conn.ofType('Mutation'), hasLength(1));

      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      final resent = conn.ofType('Mutation').single;
      expect(resent['requestId'], 0);

      conn.respondToMutation(0, 'ok', ts: 20);
      conn.respondToMutation(0, 'ok-duplicate', ts: 20);
      conn.transition(toTs: 30);
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.value, 'ok');
      expect(resolutions, 1);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a mutation queued while disconnected caps the pending backoff and '
      'goes out on the next socket', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.server.latest.serverClose();
      fake.flushMicrotasks();
      // closed-1000 → 1 s backoff floor; the queued call caps it at 250 ms.
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();
      expect(h.server.connectAttempts, 1);
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connectAttempts, 2);
      final conn = h.server.latest;
      expect(conn.receivedTypes, ['Connect', 'Mutation']);
      conn.respondToMutation(0, 'done', ts: 5);
      conn.transition(toTs: 5);
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.value, 'done');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('connectTimeout fires with phase connect while the socket is down', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server);
      final probe = FutureProbe(
        h.client.mutation<Object?>(
          'm:f',
          {},
          options: const CallOptions(connectTimeout: Duration(seconds: 5)),
        ),
      );
      fake.elapse(const Duration(seconds: 5));
      expect(probe.isDone, isTrue);
      final error = probe.error as OperationTimeoutError;
      expect(error.phase, TimeoutPhase.connect);
      expect(error.timeout, const Duration(seconds: 5));
      expect(error.connectionStatus, isNot(ConnectionStatus.ready));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('operationTimeout fires when the server never responds', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final probe = FutureProbe(
        h.client.mutation<Object?>(
          'm:f',
          {},
          options: const CallOptions(operationTimeout: Duration(seconds: 7)),
        ),
      );
      fake.flushMicrotasks();
      fake.elapse(const Duration(seconds: 7));
      expect(probe.isDone, isTrue);
      final error = probe.error as OperationTimeoutError;
      expect(error.phase, TimeoutPhase.operation);
      expect(error.connectionStatus, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('the operation timer is not restarted by a reconnect', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final probe = FutureProbe(
        h.client.mutation<Object?>(
          'm:f',
          {},
          options: const CallOptions(operationTimeout: Duration(seconds: 10)),
        ),
      );
      fake.flushMicrotasks();
      fake.elapse(const Duration(seconds: 3));
      h.server.latest.serverClose();
      fake.elapse(const Duration(seconds: 1));
      expect(h.server.connections, hasLength(2));
      expect(h.server.latest.ofType('Mutation'), hasLength(1));
      expect(probe.isDone, isFalse);
      fake.elapse(const Duration(seconds: 6)); // 10 s total since first send
      expect(probe.isDone, isTrue);
      expect(
        (probe.error as OperationTimeoutError).phase,
        TimeoutPhase.operation,
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test(
    'action resolves on ActionResponse without waiting for a transition',
    () {
      fakeAsync((fake) {
        final h = makeClient(fake);
        final conn = h.server.latest;
        final probe = FutureProbe(
          h.client.action<Object?>('v1/live/actions:requestLiveToken', {}),
        );
        fake.flushMicrotasks();
        expect(conn.ofType('Action').single['requestId'], 0);
        conn.respondToAction(0, 'live-token');
        fake.flushMicrotasks();
        expect(probe.isDone, isTrue);
        expect(probe.value, 'live-token');
        h.client.dispose();
        fake.flushMicrotasks();
      });
    },
  );

  test('action failure carries errorData', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(h.client.action<Object?>('a:f', {}));
      fake.flushMicrotasks();
      conn.failAction(0, 'no capacity', errorData: 'RATE_LIMITED');
      fake.flushMicrotasks();
      final error = probe.error as ConvexFunctionError;
      expect(error.errorMessage, 'no capacity');
      expect(error.errorData, 'RATE_LIMITED');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('an in-flight action fails with ConnectionLostError on reconnect and '
      'is never resent', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final probe = FutureProbe(h.client.action<Object?>('a:f', {}));
      fake.flushMicrotasks();
      h.server.latest.serverClose();
      fake.elapse(const Duration(seconds: 1));
      expect(probe.isDone, isTrue);
      expect(probe.error, isA<ConnectionLostError>());
      expect(h.server.latest.ofType('Action'), isEmpty);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('an action queued while disconnected is sent (not failed) on the next '
      'socket', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.server.latest.serverClose();
      fake.flushMicrotasks();
      final probe = FutureProbe(h.client.action<Object?>('a:f', {}));
      fake.flushMicrotasks();
      fake.elapse(const Duration(seconds: 1));
      final conn = h.server.latest;
      expect(conn.ofType('Action'), hasLength(1));
      conn.respondToAction(0, 'ok');
      fake.flushMicrotasks();
      expect(probe.value, 'ok');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('mutations reject HTTP fallback', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final probe = FutureProbe(
        h.client.mutation<Object?>(
          'm:f',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      expect(probe.error, isA<ArgumentError>());
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test(
    'requestIds are shared across mutations and actions and never reused',
    () {
      fakeAsync((fake) {
        final h = makeClient(fake);
        final conn = h.server.latest;
        FutureProbe(h.client.mutation<Object?>('m:one', {}));
        FutureProbe(h.client.action<Object?>('a:two', {}));
        FutureProbe(h.client.mutation<Object?>('m:three', {}));
        fake.flushMicrotasks();
        expect(conn.ofType('Mutation')[0]['requestId'], 0);
        expect(conn.ofType('Action')[0]['requestId'], 1);
        expect(conn.ofType('Mutation')[1]['requestId'], 2);
        conn.respondToMutation(0, null, ts: 1);
        conn.respondToAction(1, null);
        conn.respondToMutation(2, null, ts: 2);
        conn.transition(toTs: 2);
        fake.flushMicrotasks();
        h.client.dispose();
        fake.flushMicrotasks();
      });
    },
  );
  test('a per-call operationTimeout bounds a request that never got sent', () {
    // The voice token action rides the Convex socket and is bounded to 6 s
    // precisely because that socket can be mid-reconnect when a voice
    // reconnect needs a token. When there is no socket at all the request
    // was registered with no timer whatsoever — `sent` was false and the
    // connectTimeout default is null — so the bound never applied and the
    // call waited for the socket to come back. Observed on device as a
    // 33.7 s token fetch.
    fakeAsync((fake) {
      final server = FakeConvexServer()..refuseNext = 100;
      final h = makeClient(fake, server: server);
      expect(
        h.client.currentConnectionState.status,
        isNot(ConnectionStatus.ready),
      );

      Object? error;
      h.client
          .action<Object?>(
            'v1/live/actions:requestLiveToken',
            const {},
            options: const CallOptions(operationTimeout: Duration(seconds: 6)),
          )
          .catchError((Object e) {
            error = e;
            return null;
          });
      fake.flushMicrotasks();

      fake.elapse(const Duration(seconds: 10));
      expect(
        error,
        isA<OperationTimeoutError>(),
        reason: 'the 6 s bound must apply even with no socket to send on',
      );
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
