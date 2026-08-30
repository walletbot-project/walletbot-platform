import 'package:app/convex/client_log.dart';
import 'package:app/convex/convex_client.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

ConvexClientEvent event(String type, Map<String, Object?> data) =>
    ConvexClientEvent(at: clock.now(), type: type, data: data);

void main() {
  test(
    'a call that never comes back is reported while it is still waiting',
    () {
      // The whole point of the sweep: a completion event only exists for calls
      // that completed, so printing events alone can never show the hang that
      // is happening right now.
      final lines = <String>[];
      final log = ConvexClientLog(
        slowCall: const Duration(seconds: 2),
        sink: lines.add,
      );
      final start = DateTime.utc(2026, 1, 1);

      withClock(Clock.fixed(start), () {
        log.handle(
          event('action.request', {
            'requestId': 7,
            'udfPath': 'v1/live/actions:requestLiveToken',
            'delivered': false,
          }),
        );
      });
      lines.clear();

      withClock(Clock.fixed(start.add(const Duration(seconds: 1))), log.sweep);
      expect(lines, isEmpty, reason: 'still inside the slow-call threshold');

      withClock(Clock.fixed(start.add(const Duration(seconds: 9))), log.sweep);
      expect(lines.single, contains('WAITING'));
      expect(lines.single, contains('v1/live/actions:requestLiveToken'));
      expect(lines.single, contains('for=9000ms'));
      expect(
        lines.single,
        contains('delivered=false'),
        reason: 'says it is waiting on a reconnect, not on the server',
      );
    },
  );

  test('a completed call stops being reported', () {
    final lines = <String>[];
    final log = ConvexClientLog(
      slowCall: const Duration(seconds: 2),
      sink: lines.add,
    );
    final start = DateTime.utc(2026, 1, 1);

    withClock(Clock.fixed(start), () {
      log.handle(
        event('mutation.request', {
          'requestId': 3,
          'udfPath': 'v1/voice/sessions:appendEvents',
          'delivered': true,
        }),
      );
      log.handle(
        event('mutation.completed', {'requestId': 3, 'elapsedMs': 40}),
      );
    });
    lines.clear();

    withClock(Clock.fixed(start.add(const Duration(minutes: 1))), log.sweep);
    expect(lines, isEmpty);
  });

  test('a slow completion is flagged and a fast one is not', () {
    final lines = <String>[];
    final log = ConvexClientLog(
      slowCall: const Duration(seconds: 2),
      sink: lines.add,
    );

    log.handle(event('action.completed', {'udfPath': 'a', 'elapsedMs': 120}));
    log.handle(event('action.completed', {'udfPath': 'b', 'elapsedMs': 9000}));

    expect(lines.first, isNot(contains('SLOW')));
    expect(lines.last, contains('SLOW'));
    expect(lines.last, contains('elapsedMs=9000'));
  });

  test('muted event types are dropped', () {
    final lines = <String>[];
    final log = ConvexClientLog(
      muted: const {'query.subscribe'},
      sink: lines.add,
    );

    log.handle(event('query.subscribe', {'queryId': 1}));
    log.handle(event('socket.ready', const {}));

    expect(lines.single, contains('socket.ready'));
  });
}
