import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/convex_client.dart';

import 'helpers/fake_convex_server.dart';

void main() {
  test('inactivity watchdog closes a silent socket and reconnects', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final first = h.server.latest;
      fake.elapse(const Duration(seconds: 45));
      expect(first.closedByClient, isTrue);
      expect(first.clientCloseReason, 'InactiveServer');
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connections, hasLength(2));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('server pings keep the watchdog quiet', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      for (var i = 0; i < 6; i++) {
        fake.elapse(const Duration(seconds: 15));
        conn.ping();
      }
      expect(h.server.connections, hasLength(1));
      expect(conn.closed, isFalse);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('handshake timeout abandons a stuck upgrade and retries', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..hangNext = 1;
      final h = makeClient(fake, server: server);
      expect(server.connectAttempts, 1);
      expect(server.connections, isEmpty);
      fake.elapse(const Duration(seconds: 10)); // handshake timeout
      fake.elapse(const Duration(milliseconds: 250));
      expect(server.connectAttempts, 2);
      expect(server.connections, hasLength(1));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('backoff grows exponentially with deterministic jitter', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..refuseNext = 4;
      final h = makeClient(fake, server: server);
      // Attempts at t=0, 250 ms, 750 ms, 1750 ms, 3750 ms (250·2^k floors).
      expect(server.connectAttempts, 1);
      fake.elapse(const Duration(milliseconds: 249));
      expect(server.connectAttempts, 1);
      fake.elapse(const Duration(milliseconds: 1));
      expect(server.connectAttempts, 2);
      fake.elapse(const Duration(milliseconds: 499));
      expect(server.connectAttempts, 2);
      fake.elapse(const Duration(milliseconds: 1));
      expect(server.connectAttempts, 3);
      fake.elapse(const Duration(milliseconds: 1000));
      expect(server.connectAttempts, 4);
      fake.elapse(const Duration(milliseconds: 2000));
      expect(server.connectAttempts, 5);
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('retries reset only after a full resync, not on a bare reconnect', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.client.subscribe('q:f', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();
      h.server.refuseNext = 2;
      h.server.latest.serverClose();
      // Attempts: +1 s (refused), +1.5 s (refused), +2.5 s (succeeds) — the
      // floor is 1 s for the server close, then 250 ms for connect errors.
      fake.elapse(const Duration(seconds: 3));
      expect(h.server.connections, hasLength(2));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      // Reconnected but the re-added query is unanswered: not resynced.
      expect(h.client.currentConnectionState.retries, 3);

      h.server.latest.transition(
        toQuerySet: 1,
        toTs: 9,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': 1,
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(h.client.currentConnectionState.retries, 0);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a connectivity-regained hint skips the pending backoff', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..refuseNext = 5;
      final h = makeClient(fake, server: server);
      fake.elapse(const Duration(milliseconds: 750)); // 3 failed attempts
      expect(server.connectAttempts, 3);
      // Next attempt would wait 2 s; the hint connects now.
      server.refuseNext = 0;
      h.client.onNetworkAvailable();
      fake.flushMicrotasks();
      expect(server.connectAttempts, 4);
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('app-resume hint reconnects immediately while disconnected', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.server.latest.serverClose(); // 1 s backoff pending
      fake.flushMicrotasks();
      h.client.onAppResumed();
      fake.flushMicrotasks();
      expect(h.server.connections, hasLength(2));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('reconnectNow really closes and reopens the socket', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final first = h.server.latest;
      h.client.reconnectNow();
      fake.flushMicrotasks();
      expect(first.closedByClient, isTrue);
      expect(first.clientCloseReason, 'ClientReconnect');
      expect(h.server.connections, hasLength(2));
      final connect = h.server.latest.ofType('Connect').single;
      expect(connect['sessionId'], 'session-1');
      expect(connect['connectionCount'], 2);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a transition from an impossible version tears the socket down and '
      'resubscribes on the next one', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.client.subscribe('q:f', {}, onUpdate: (_) {}, onError: (_) {});
      fake.flushMicrotasks();
      final first = h.server.latest;
      first.querySet = 5; // wrong: client never acknowledged these versions
      first.transition(toQuerySet: 6, toTs: 1);
      fake.flushMicrotasks();
      expect(first.closedByClient, isTrue);
      expect(first.clientCloseReason, startsWith('ProtocolError'));
      fake.elapse(const Duration(milliseconds: 250));
      final second = h.server.latest;
      expect(second.receivedTypes, ['Connect', 'ModifyQuerySet']);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('chunked transitions are reassembled end-to-end', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final updates = <Object?>[];
      h.client.subscribe('q:f', {}, onUpdate: updates.add, onError: (_) {});
      fake.flushMicrotasks();
      h.server.latest.chunkedTransition(
        toQuerySet: 1,
        toTs: 8,
        parts: 3,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': {'nested': 'value'},
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(updates, [
        {'nested': 'value'},
      ]);
      expect(h.server.connections, hasLength(1));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a non-chunk frame interleaved with chunks discards the buffer '
      'without killing the socket', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final updates = <Object?>[];
      h.client.subscribe('q:f', {}, onUpdate: updates.add, onError: (_) {});
      fake.flushMicrotasks();
      final conn = h.server.latest;
      final payload = jsonEncode({
        'type': 'Transition',
        'startVersion': conn.versionMap(),
        'endVersion': conn.versionMap(),
        'modifications': <Object?>[],
      });
      conn.send({
        'type': 'TransitionChunk',
        'chunk': payload.substring(0, 10),
        'partNumber': 0,
        'totalParts': 2,
        'transitionId': 'partial',
      });
      conn.ping(); // discards the partial buffer
      fake.flushMicrotasks();
      expect(h.server.connections, hasLength(1));
      conn.transition(
        toQuerySet: 1,
        toTs: 2,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': 'after-discard',
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(updates, ['after-discard']);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('an out-of-order chunk is a protocol error and reconnects', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      conn.send({
        'type': 'TransitionChunk',
        'chunk': 'xx',
        'partNumber': 1,
        'totalParts': 2,
        'transitionId': 'oops',
      });
      fake.flushMicrotasks();
      expect(conn.closedByClient, isTrue);
      expect(conn.clientCloseReason, startsWith('ProtocolError'));
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connections, hasLength(2));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('FatalError fails everything, never reconnects, and poisons the '
      'client until dispose', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final subErrors = <ConvexFunctionError>[];
      h.client.subscribe('q:f', {}, onUpdate: (_) {}, onError: subErrors.add);
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();

      conn.fatal('deployment deleted');
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.error, isA<ConvexFatalError>());
      expect(subErrors, hasLength(1));
      expect(subErrors.single.errorMessage, contains('deployment deleted'));
      expect(
        h.client.currentConnectionState.status,
        ConnectionStatus.disconnected,
      );

      fake.elapse(const Duration(minutes: 2));
      expect(h.server.connections, hasLength(1)); // no reconnect, ever

      final second = FutureProbe(h.client.mutation<Object?>('m:g', {}));
      fake.flushMicrotasks();
      expect(second.error, isA<ConvexFatalError>());
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('dispose stops reconnecting, fails pending requests, and closes '
      'the streams', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();
      var connectionDone = false;
      var authDone = false;
      h.client.connectionState.listen(
        null,
        onDone: () => connectionDone = true,
      );
      h.client.authState.listen(null, onDone: () => authDone = true);

      h.client.dispose();
      fake.flushMicrotasks();
      expect(probe.error, isA<ClientDisposedError>());
      expect(conn.closedByClient, isTrue);
      expect(conn.clientCloseReason, 'ClientDisposed');
      expect(connectionDone, isTrue);
      expect(authDone, isTrue);

      fake.elapse(const Duration(minutes: 2));
      expect(h.server.connections, hasLength(1));

      final after = FutureProbe(h.client.mutation<Object?>('m:g', {}));
      fake.flushMicrotasks();
      expect(after.error, isA<ClientDisposedError>());
    });
  });

  test('maxReconnectAttempts stops the retry loop until an explicit hint', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..refuseNext = 3;
      final h = makeClient(
        fake,
        server: server,
        config: testConfig(maxReconnectAttempts: 2),
      );
      fake.elapse(const Duration(minutes: 2));
      expect(server.connectAttempts, 3); // initial + 2 retries, then gave up
      expect(
        h.client.currentConnectionState.lastCloseReason,
        'ReconnectAttemptsExhausted',
      );
      h.client.onNetworkAvailable();
      fake.flushMicrotasks();
      expect(server.connectAttempts, 4);
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a hung token fetch is timeboxed: the restart completes '
      'unauthenticated instead of wedging in connecting', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      var hang = false;
      h.client.setAuth(
        fetchToken: ({required bool forceRefresh}) {
          if (hang) return Future.any([]); // never completes
          return Future.value(makeJwt());
        },
      );
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();

      hang = true;
      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      expect(h.server.connections, hasLength(2));
      expect(conn.receivedTypes, ['Connect']); // parked on the fetch
      expect(
        h.client.currentConnectionState.status,
        ConnectionStatus.connecting,
      );
      fake.elapse(const Duration(seconds: 15)); // authFetchTimeout
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      expect(conn.ofType('Authenticate'), isEmpty);

      // The fetcher recovers: a reconnect authenticates again.
      hang = false;
      h.client.reconnectNow();
      fake.flushMicrotasks();
      conn = h.server.latest;
      expect(h.server.connections, hasLength(3));
      expect(conn.receivedTypes.take(2), ['Connect', 'Authenticate']);
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticated);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('the restart timeout abandons a wedged restart, and the abandoned '
      'continuation never writes onto the next socket', () {
    fakeAsync((fake) {
      final h = makeClient(
        fake,
        config: testConfig(authFetchTimeout: const Duration(seconds: 60)),
      );
      var conn = h.server.latest;
      var hang = false;
      h.client.setAuth(
        fetchToken: ({required bool forceRefresh}) {
          if (hang) return Future.any([]);
          return Future.value(makeJwt());
        },
      );
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();

      hang = true;
      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      expect(conn.receivedTypes, ['Connect']);
      // Keep the watchdog fed so only the restart timeout (20 s) can fire.
      fake.elapse(const Duration(seconds: 15));
      conn.ping();
      fake.elapse(const Duration(seconds: 5));
      expect(conn.closedByClient, isTrue);
      expect(conn.clientCloseReason, startsWith('RestartError'));

      // The next socket restarts; the poisoned fetch keeps it parked, but
      // the abandoned restart must not have leaked any frame into it.
      fake.elapse(const Duration(seconds: 1));
      final third = h.server.latest;
      expect(h.server.connections, hasLength(3));
      expect(third.receivedTypes, ['Connect']);
      // Until the 60 s fetch timebox (started at +1 s) clears the poisoned
      // future at +61 s, restarts keep cycling on the 20 s restart timeout —
      // bounded churn instead of a permanent wedge — and then the socket
      // settles ready, unauthenticated.
      fake.elapse(const Duration(seconds: 40));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      expect(h.server.latest.ofType('Authenticate'), isEmpty);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('overload close reasons back off from the 3 s floor', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.server.latest.serverClose(
        code: 1013,
        reason: 'TooManyConcurrentRequests: try again later',
      );
      fake.flushMicrotasks();
      fake.elapse(const Duration(milliseconds: 2999));
      expect(h.server.connections, hasLength(1));
      fake.elapse(const Duration(milliseconds: 1));
      expect(h.server.connections, hasLength(2));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
