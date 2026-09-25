import 'dart:async';
import 'package:app/voice/live_tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> call(String id) => {
  'functionCalls': [
    {'id': id, 'name': 'addExpense', 'args': <String, dynamic>{}},
  ],
};

void main() {
  test(
    'duplicate and cancelled calls do not repeat writes; results stay on their socket',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var epoch = 1;
      final writes = <String>[];
      final results = <String>[];
      final responses = <Map<String, dynamic>>[];
      final dispatcher = LiveToolDispatcher(
        execute: (name, _) {
          writes.add(name);
          return pending.future;
        },
        isCurrent: (value) => value == epoch,
        onCall: (_, _, _) {},
        onResult: (id, _, _) => results.add(id),
        respond: (response, _) => responses.add(response),
      );
      final first = dispatcher.dispatch(call('a'), 1);
      unawaited(dispatcher.dispatch(call('a'), 1));
      unawaited(dispatcher.dispatch(call('b'), 1));
      dispatcher.cancel(['b'], 1);
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));
      epoch = 2;
      pending.complete({'ok': true});
      await first;
      await dispatcher.settled;
      expect(writes, hasLength(1));
      expect(results, [
        'a',
      ]); // Committed outcome retained for reconnect context.
      expect(responses, isEmpty);
      await dispatcher.dispatch(call('a'), 2); // IDs are per connection.
      expect(writes, hasLength(2));
      expect(responses, hasLength(1));
    },
  );

  test(
    'cancellation during execution records outcome but suppresses response',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final results = <String>[];
      final dispatcher = LiveToolDispatcher(
        execute: (_, _) => pending.future,
        isCurrent: (_) => true,
        onCall: (_, _, _) {},
        onResult: (id, _, _) => results.add(id),
        respond: (_, _) => fail('cancelled call sent a response'),
      );
      final work = dispatcher.dispatch(call('a'), 1);
      await Future<void>.delayed(Duration.zero);
      dispatcher.cancel(['a'], 1);
      pending.complete({'ok': true});
      await work;
      expect(results, ['a']);
    },
  );

  test(
    'executor failures return a result and do not poison later calls',
    () async {
      final responses = <Map<String, dynamic>>[];
      final dispatcher = LiveToolDispatcher(
        execute: (_, _) async => throw StateError('write failed'),
        isCurrent: (_) => true,
        onCall: (_, _, _) {},
        onResult: (_, _, _) {},
        respond: (response, _) => responses.add(response),
      );
      await dispatcher.dispatch(call('a'), 1);
      await dispatcher.dispatch(call('b'), 1);
      expect(responses, hasLength(2));
      expect(
        responses
            .first['toolResponse']['functionResponses'][0]['response']['result']['ok'],
        false,
      );
    },
  );

  test('background tools run beside the queue and answer when idle', () async {
    final write = Completer<Map<String, dynamic>>();
    final responses = <Map<String, dynamic>>[];
    final dispatcher = LiveToolDispatcher(
      backgroundTools: const {'readAttachment'},
      execute: (name, _) => name == 'readAttachment'
          ? Future.value({'ok': true, 'answer': 'Total'})
          : write.future,
      isCurrent: (_) => true,
      onCall: (_, _, _) {},
      onResult: (_, _, _) {},
      respond: (response, _) => responses.add(response),
    );
    unawaited(dispatcher.dispatch(call('w'), 1));
    unawaited(
      dispatcher.dispatch({
        'functionCalls': [
          {'id': 'r', 'name': 'readAttachment', 'args': <String, dynamic>{}},
        ],
      }, 1),
    );
    await Future<void>.delayed(Duration.zero);
    expect(responses, [
      {
        'toolResponse': {
          'functionResponses': [
            {
              'id': 'r',
              'name': 'readAttachment',
              'response': {
                'result': {'ok': true, 'answer': 'Total'},
              },
              'scheduling': 'WHEN_IDLE',
            },
          ],
        },
      },
    ]);
    write.complete({'ok': true});
    await dispatcher.settled;
    expect(responses, hasLength(2));
    final last =
        (responses.last['toolResponse'] as Map)['functionResponses'] as List;
    expect((last.single as Map).containsKey('scheduling'), isFalse);
  });
}
