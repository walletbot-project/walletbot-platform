import 'package:app/convex/convex_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_convex_server.dart';

/// The recovery paths that only fire on a real device: coming back from a long
/// background with a socket the OS quietly stranded, and changing networks
/// without ever going offline.
void main() {
  test('resuming with a stranded socket replaces it instead of waiting for '
      'the watchdog', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final stranded = h.server.latest;

      // Backgrounded past the inactivity threshold. The process was suspended,
      // so the watchdog timer did not get to run while away.
      fake.elapse(const Duration(seconds: 44));
      h.client.onAppResumed();
      fake.flushMicrotasks();

      expect(stranded.closedByClient, isFalse, reason: 'still inside 45 s');

      fake.elapse(const Duration(seconds: 2));
      h.client.onAppResumed();
      fake.flushMicrotasks();
      expect(stranded.closedByClient, isTrue);
      expect(stranded.clientCloseReason, 'InactiveServer');
      fake.elapse(const Duration(milliseconds: 250));
      expect(h.server.connections, hasLength(2));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a network change replaces a socket that still looks healthy', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final stale = h.server.latest;
      // A frame just arrived, so nothing about this socket looks wrong — but
      // WiFi just handed over to cellular and it is bound to the old route.
      stale.ping();
      fake.flushMicrotasks();

      h.client.onNetworkChanged();
      fake.flushMicrotasks();

      expect(stale.closedByClient, isTrue);
      expect(stale.clientCloseReason, 'ClientReconnect');
      expect(h.server.connections, hasLength(2));
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a network change while already disconnected just connects', () {
    fakeAsync((fake) {
      final server = FakeConvexServer()..refuseNext = 3;
      final h = makeClient(fake, server: server);
      fake.elapse(const Duration(milliseconds: 750));
      expect(server.connectAttempts, 3);

      server.refuseNext = 0;
      h.client.onNetworkChanged();
      fake.flushMicrotasks();
      expect(server.connectAttempts, 4);
      expect(h.client.currentConnectionState.status, ConnectionStatus.ready);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('a subscription survives a network change and keeps delivering', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      final values = <Object?>[];
      h.client.subscribe(
        'todos:list',
        const {},
        onUpdate: values.add,
        onError: (_) {},
      );
      fake.flushMicrotasks();
      h.server.latest.transition(
        toQuerySet: 1,
        toTs: 1,
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
      expect(values, [1]);

      h.client.onNetworkChanged();
      fake.flushMicrotasks();

      // The fresh socket re-adds the query as a 0 → 1 ModifyQuerySet.
      final readd = h.server.latest.ofType('ModifyQuerySet').single;
      expect(readd['baseVersion'], 0);
      expect(readd['newVersion'], 1);
      h.server.latest.transition(
        toQuerySet: 1,
        toTs: 1,
        modifications: [
          {
            'type': 'QueryUpdated',
            'queryId': 0,
            'value': 2,
            'logLines': <String>[],
            'journal': null,
          },
        ],
      );
      fake.flushMicrotasks();
      expect(values, [1, 2]);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('an in-flight mutation survives a network change exactly once', () {
    fakeAsync((fake) {
      final h = makeClient(fake);
      var resolved = false;
      h.client
          .mutation<Object?>('todos:add', const {'text': 'x'})
          .then((_) => resolved = true);
      fake.flushMicrotasks();
      final firstRequest = h.server.latest.ofType('Mutation').single;

      h.client.onNetworkChanged();
      fake.flushMicrotasks();

      final resent = h.server.latest.ofType('Mutation').single;
      expect(resent['requestId'], firstRequest['requestId']);
      expect(
        h.server.latest.ofType('Connect').single['sessionId'],
        'session-1',
      );
      expect(resolved, isFalse);

      h.server.latest.respondToMutation(
        resent['requestId']! as int,
        null,
        ts: 1,
      );
      h.server.latest.transition(toTs: 1);
      fake.flushMicrotasks();
      expect(resolved, isTrue);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
