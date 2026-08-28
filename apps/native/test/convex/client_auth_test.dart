import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/convex_client.dart';

import 'helpers/fake_convex_server.dart';

/// A scriptable token fetcher that records every call's forceRefresh flag.
class FetcherScript {
  FetcherScript({this.ttl = const Duration(hours: 24)});

  final Duration ttl;
  final List<bool> calls = [];
  int _serial = 0;
  Object? throwWith;
  bool returnNull = false;

  final List<String> issued = [];

  Future<String?> call({required bool forceRefresh}) {
    calls.add(forceRefresh);
    final error = throwWith;
    if (error != null) return Future.error(error);
    if (returnNull) return Future.value(null);
    final token = makeJwt(ttl: ttl, sub: 'u${_serial++}');
    issued.add(token);
    return Future.value(token);
  }
}

void main() {
  test('setAuth: cached token, server confirmation, immediate fresh upgrade, '
      'scheduled refresh at exp - leeway', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript(ttl: const Duration(minutes: 10));
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      expect(fetcher.calls, [false]);
      var auths = conn.ofType('Authenticate');
      expect(auths, hasLength(1));
      expect(auths[0]['tokenType'], 'User');
      expect(auths[0]['value'], fetcher.issued[0]);
      expect(auths[0]['baseVersion'], 0);
      expect(h.client.currentAuthState, AuthState.authenticating);

      conn.confirmAuth();
      fake.flushMicrotasks();
      // Cached token confirmed → immediate forced upgrade (§6.2).
      expect(fetcher.calls, [false, true]);
      auths = conn.ofType('Authenticate');
      expect(auths, hasLength(2));
      expect(auths[1]['value'], fetcher.issued[1]);
      expect(auths[1]['baseVersion'], 1);
      expect(h.client.currentAuthState, AuthState.authenticated);

      conn.confirmAuth();
      fake.flushMicrotasks();
      // Refresh scheduled at exp − 60 s = 9 minutes from issue. Keep the
      // watchdog fed while waiting.
      for (var i = 0; i < 17; i++) {
        fake.elapse(const Duration(seconds: 30));
        conn.ping();
      }
      fake.elapse(const Duration(seconds: 30)); // t = 9 min
      fake.flushMicrotasks();
      expect(fetcher.calls, [false, true, true]);
      auths = conn.ofType('Authenticate');
      expect(auths, hasLength(3));
      expect(auths[2]['baseVersion'], 2);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('every reconnect authenticates with a forced-fresh token', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(fetcher.calls, [false, true]);

      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      expect(fetcher.calls, [false, true, true]);
      final authenticate = conn.ofType('Authenticate').single;
      expect(authenticate['baseVersion'], 0);
      expect(authenticate['value'], fetcher.issued.last);
      expect(conn.receivedTypes.take(2), ['Connect', 'Authenticate']);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('AuthError filter: a query that ran with the dying token is ignored '
      'while a newer token awaits confirmation', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      // Authenticate sent, confirmation pending.
      conn.authError(
        'stale query auth',
        baseVersion: 0,
        authUpdateAttempted: false,
      );
      fake.flushMicrotasks();
      expect(h.server.connections, hasLength(1));
      expect(h.client.currentAuthState, AuthState.authenticating);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('AuthError filter: a baseVersion older than the latest attempt is '
      'ignored', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      // Two Authenticates sent (base 0 and 1); an error about base 0 is stale.
      conn.authError('stale', baseVersion: 0);
      fake.flushMicrotasks();
      expect(h.server.connections, hasLength(1));
      expect(h.client.currentAuthState, AuthState.authenticated);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('mid-session AuthError: one restart with one fresh fetch, no storm', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticated);

      conn.authError('token expired', baseVersion: 1);
      fake.flushMicrotasks();
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connections, hasLength(2));
      conn = h.server.latest;
      expect(conn.ofType('Authenticate').single['baseVersion'], 0);
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticated);
      // No further reconnects.
      fake.elapse(const Duration(seconds: 5));
      conn.ping();
      expect(h.server.connections, hasLength(2));
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('two consecutive fresh-token rejections downgrade to unauthenticated '
      'instead of looping, then the retry timer recovers', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      // Reject the cached-token attempt: restart, no strike.
      conn.authError('rejected', baseVersion: 0);
      fake.flushMicrotasks();
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connections, hasLength(2));
      conn = h.server.latest;
      expect(conn.ofType('Authenticate').single['tokenType'], 'User');

      // Strike 1: fresh token rejected → one more restart.
      conn.authError('rejected', baseVersion: 0);
      fake.flushMicrotasks();
      fake.elapse(const Duration(milliseconds: 500));
      expect(h.server.connections, hasLength(3));
      conn = h.server.latest;

      // Strike 2: give up — downgrade on the same socket, no restart.
      conn.authError('rejected', baseVersion: 0);
      fake.flushMicrotasks();
      final auths = conn.ofType('Authenticate');
      expect(auths, hasLength(2));
      expect(auths[1]['tokenType'], 'None');
      expect(auths[1]['baseVersion'], 0);
      expect(h.client.currentAuthState, AuthState.refreshFailed);
      expect(h.server.connections, hasLength(3));

      // Server applies the None (identity advances).
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.server.connections, hasLength(3));

      // Retry timer: fresh fetch, Authenticate with the advanced base.
      for (var i = 0; i < 2; i++) {
        fake.elapse(const Duration(seconds: 30));
        conn.ping();
      }
      fake.flushMicrotasks();
      final retryAuth = conn.ofType('Authenticate').last;
      expect(retryAuth['tokenType'], 'User');
      expect(retryAuth['baseVersion'], 1);
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticated);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('clearAuth sends tokenType None and reconnects unauthenticated', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();

      h.client.clearAuth();
      fake.flushMicrotasks();
      final none = conn.ofType('Authenticate').last;
      expect(none['tokenType'], 'None');
      expect(none['baseVersion'], 2);
      expect(h.client.currentAuthState, AuthState.unauthenticated);

      conn.serverClose();
      fake.elapse(const Duration(seconds: 1));
      conn = h.server.latest;
      expect(conn.ofType('Authenticate'), isEmpty);
      expect(fetcher.calls, [false, true]);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a fetcher returning null means signed out: no Authenticate sent', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript()..returnNull = true;
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      expect(conn.ofType('Authenticate'), isEmpty);
      expect(h.client.currentAuthState, AuthState.unauthenticated);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('outgoing traffic pauses during the initial token fetch so mutations '
      'cannot fire before Authenticate', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final gate = Completer<String?>();
      h.client.setAuth(
        fetchToken: ({required bool forceRefresh}) => gate.future,
      );
      fake.flushMicrotasks();
      final probe = FutureProbe(h.client.mutation<Object?>('m:f', {}));
      fake.flushMicrotasks();
      expect(conn.ofType('Mutation'), isEmpty);

      gate.complete(makeJwt());
      fake.flushMicrotasks();
      expect(conn.receivedTypes, ['Connect', 'Authenticate', 'Mutation']);
      conn.respondToMutation(0, 'ok', ts: 1);
      conn.transition(toTs: 1);
      fake.flushMicrotasks();
      expect(probe.value, 'ok');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('transient fetch failures schedule a retry and downgrade after the '
      'strike limit without a reconnect storm', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript()..throwWith = Exception('network down');
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticating);
      expect(fetcher.calls, hasLength(1));

      // Retry timer (60 s): second failure hits the strike limit.
      for (var i = 0; i < 2; i++) {
        fake.elapse(const Duration(seconds: 30));
        conn.ping();
      }
      fake.flushMicrotasks();
      expect(fetcher.calls, hasLength(2));
      expect(h.client.currentAuthState, AuthState.refreshFailed);
      expect(h.server.connections, hasLength(1)); // no socket churn

      // Fetcher recovers on the next retry tick.
      fetcher.throwWith = null;
      for (var i = 0; i < 2; i++) {
        fake.elapse(const Duration(seconds: 30));
        conn.ping();
      }
      fake.flushMicrotasks();
      final auth = conn.ofType('Authenticate').last;
      expect(auth['tokenType'], 'User');
      conn.confirmAuth();
      fake.flushMicrotasks();
      expect(h.client.currentAuthState, AuthState.authenticated);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('setAuth while disconnected authenticates on the next socket', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      h.server.latest.serverClose();
      fake.flushMicrotasks();
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      expect(fetcher.calls, isEmpty); // nothing to send yet
      fake.elapse(const Duration(seconds: 1));
      final conn = h.server.latest;
      expect(conn.receivedTypes.take(2), ['Connect', 'Authenticate']);
      expect(fetcher.calls, [true]); // restart always forces fresh
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('validToken caches the fetched token until near expiry', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript(ttl: const Duration(minutes: 5));
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      final callsAfterSetup = fetcher.calls.length;

      String? token;
      h.client.validToken().then((t) => token = t);
      fake.flushMicrotasks();
      expect(token, fetcher.issued.last);
      expect(fetcher.calls.length, callsAfterSetup); // served from cache
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('auth state stream reports the full lifecycle', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final conn = h.server.latest;
      final fetcher = FetcherScript();
      h.client.setAuth(fetchToken: fetcher.call);
      fake.flushMicrotasks();
      conn.confirmAuth();
      fake.flushMicrotasks();
      h.client.clearAuth();
      fake.flushMicrotasks();
      expect(h.authStates, [
        AuthState.authenticating,
        AuthState.authenticated,
        AuthState.unauthenticated,
      ]);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
