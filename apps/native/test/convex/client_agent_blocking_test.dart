import 'dart:async';

import 'package:app/convex/convex_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_convex_server.dart';

/// The voice agent calls Convex for one thing it cannot do without: a Gemini
/// Live token. Everything else it sends is replication that must never hold
/// up a conversation. These cover the paths where the client could make the
/// agent wait longer than the caller asked for.
void main() {
  test(
    'an explicit operationTimeout covers the auth step of an HTTP fallback',
    () {
      // The fallback needs a bearer token, and fetching one has its own 15 s
      // bound. Resolving it before starting the caller's clock meant a 6 s
      // deadline could take 15 s plus the post: the agent asked to wait 6 s for
      // a token and waited far longer for the call that fetches it.
      fakeAsync((fake) {
        final authGate = Completer<String?>();
        final server = FakeConvexServer()..hangNext = 100;
        final h = makeClient(
          fake,
          server: server,
          httpPoster: (_, _, _) async =>
              const HttpPostResponse(200, '{"status":"success","value":null}'),
        );
        h.client.setAuth(
          fetchToken: ({required bool forceRefresh}) => authGate.future,
        );
        fake.flushMicrotasks();

        final probe = FutureProbe(
          h.client.action<Object?>(
            'v1/live/actions:requestLiveToken',
            const {},
            options: const CallOptions(
              operationTimeout: Duration(seconds: 6),
              httpFallback: HttpFallback.whenNotReady,
            ),
          ),
        );

        fake.elapse(const Duration(seconds: 5));
        expect(probe.isDone, isFalse);
        fake.elapse(const Duration(seconds: 2));
        expect(probe.isDone, isTrue);
        expect(probe.error, isA<OperationTimeoutError>());

        authGate.complete(null);
        fake.flushMicrotasks();
        h.client.dispose();
        fake.flushMicrotasks();
      });
    },
  );

  test(
    'a mutation with a connectTimeout gives up instead of waiting out a backoff',
    () {
      // `sendOrBuffer` returns false only when there is no socket object at
      // all, which is the whole reconnect-backoff window. A mutation registered
      // then arms no timer of its own, so without an explicit bound the voice
      // outbox drain sat on it forever and never released the flush that owns
      // it.
      fakeAsync((fake) {
        final server = FakeConvexServer()..refuseNext = 100;
        final h = makeClient(fake, server: server);
        expect(
          h.client.currentConnectionState.status,
          isNot(ConnectionStatus.ready),
        );

        final bounded = FutureProbe(
          h.client.mutation<Object?>(
            'v1/voice/sessions:appendEvents',
            const {},
            options: const CallOptions(connectTimeout: Duration(seconds: 10)),
          ),
        );
        final unbounded = FutureProbe(
          h.client.mutation<Object?>('v1/sync/mutations:push', const {}),
        );

        fake.elapse(const Duration(seconds: 11));
        expect(bounded.isDone, isTrue);
        expect(bounded.error, isA<OperationTimeoutError>());
        expect(
          (bounded.error! as OperationTimeoutError).phase,
          TimeoutPhase.connect,
        );

        // The offline write still waits: that is what makes it survive to the
        // next connection, and only the caller can say it cannot afford to.
        expect(unbounded.isDone, isFalse);

        h.client.dispose();
        fake.flushMicrotasks();
      });
    },
  );

  test(
    'every call emits a completion or failure event carrying its elapsed time',
    () {
      fakeAsync((fake) {
        final h = makeClient(fake);
        final conn = h.server.latest;
        expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
        h.events.clear();

        final probe = FutureProbe(
          h.client.action<Object?>(
            'v1/live/actions:requestLiveToken',
            const {},
          ),
        );
        final request = h.events.singleWhere((e) => e.type == 'action.request');
        expect(request.data['udfPath'], 'v1/live/actions:requestLiveToken');
        expect(request.data['delivered'], isTrue);
        expect(request.data['connection'], 'ready');

        fake.elapse(const Duration(seconds: 3));
        conn.respondToAction(0, 'tok');
        fake.flushMicrotasks();

        expect(probe.isDone, isTrue);
        final completed = h.events.singleWhere(
          (e) => e.type == 'action.completed',
        );
        expect(completed.data['elapsedMs'], 3000);
        expect(completed.data['udfPath'], 'v1/live/actions:requestLiveToken');

        h.client.dispose();
        fake.flushMicrotasks();
      });
    },
  );

  test('a call that times out reports the failure and its elapsed time', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.events.clear();

      final probe = FutureProbe(
        h.client.action<Object?>(
          'v1/live/actions:requestLiveToken',
          const {},
          options: const CallOptions(operationTimeout: Duration(seconds: 6)),
        ),
      );
      fake.elapse(const Duration(seconds: 7));

      expect(probe.isDone, isTrue);
      final failed = h.events.singleWhere((e) => e.type == 'action.failed');
      expect(failed.data['elapsedMs'], 6000);
      expect(
        failed.data['error'],
        contains('v1/live/actions:requestLiveToken'),
      );

      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
