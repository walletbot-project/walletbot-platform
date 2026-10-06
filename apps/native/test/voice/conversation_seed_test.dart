import 'package:app/voice/voice_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reconnect context preserves completed tool arguments and persisted IDs',
    () {
      final seed = buildConversationSeed([
        VoiceUserTranscriptDelta('coffee 3000'),
        VoiceToolCallEvent(id: 'a', name: 'addExpense', args: {'amount': 3000}),
        VoiceToolResultEvent(
          id: 'a',
          name: 'addExpense',
          result: {'ok': true, 'id': 'saved-id'},
        ),
      ]);
      expect(seed, contains('Recorded tool outcome:'));
      expect(seed, contains('"amount":3000'));
      expect(seed, contains('"id":"saved-id"'));
      expect(seed, contains('do not repeat a successful write'));
    },
  );
  test('builds User/Assistant transcript from deltas and turn boundaries', () {
    final seed = buildConversationSeed([
      VoiceUserTranscriptDelta('¿Qué eventos '),
      VoiceUserTranscriptDelta('tengo esta semana?'),
      VoiceAgentTranscriptDelta('Esta semana tuviste '),
      VoiceAgentTranscriptDelta('un gasto de veinticinco mil pesos.'),
      VoiceAgentTurnComplete(),
      VoiceUserTranscriptDelta('Y gasté 10 000 pesos en pizza.'),
      VoiceAgentTranscriptDelta('De acuerdo. ¿Con qué cuenta pagaste?'),
      VoiceAgentInterruptedEvent(),
    ]);

    expect(seed, isNotNull);
    expect(
      seed,
      stringContainsInOrder([
        'User: ¿Qué eventos tengo esta semana?',
        'Assistant: Esta semana tuviste un gasto de veinticinco mil pesos.',
        'User: Y gasté 10 000 pesos en pizza.',
        'Assistant: De acuerdo. ¿Con qué cuenta pagaste?',
      ]),
    );
    expect(seed, contains('Do not greet again'));
  });

  test('typed messages appear as user lines', () {
    final seed = buildConversationSeed([
      VoiceClientActionEvent('send_message', details: const {'text': 'hola'}),
      VoiceAgentTranscriptDelta('¡Hola!'),
      VoiceAgentTurnComplete(),
    ]);
    expect(seed, contains('User: hola'));
    expect(seed, contains('Assistant: ¡Hola!'));
  });

  test('non-conversation client actions are ignored', () {
    final seed = buildConversationSeed([
      VoiceClientActionEvent('mute_changed', details: const {'muted': true}),
      VoiceClientActionEvent('screen_attached'),
    ]);
    expect(seed, isNull);
  });

  test('trailing pending texts are excluded, delivered ones kept', () {
    final seed = buildConversationSeed(
      [
        VoiceClientActionEvent('send_message', details: const {'text': 'hola'}),
        VoiceAgentTranscriptDelta('¡Hola! ¿En qué te ayudo?'),
        VoiceAgentTurnComplete(),
        VoiceClientActionEvent('send_message', details: const {'text': 'kek'}),
        VoiceClientActionEvent('send_message', details: const {'text': 'hey'}),
      ],
      pendingTexts: const ['kek', 'hey'],
    );

    expect(seed, contains('User: hola'));
    expect(seed, isNot(contains('kek')));
    expect(seed, isNot(contains('hey')));
  });

  test('a delivered duplicate of a pending text is not over-trimmed', () {
    final seed = buildConversationSeed(
      [
        VoiceClientActionEvent('send_message', details: const {'text': 'hola'}),
        VoiceAgentTranscriptDelta('¡Hola!'),
        VoiceAgentTurnComplete(),
        VoiceClientActionEvent('send_message', details: const {'text': 'hola'}),
      ],
      pendingTexts: const ['hola'],
    );

    // Only the trailing queued copy is trimmed; the answered one stays.
    expect(seed, contains('User: hola'));
    expect(seed, contains('Assistant: ¡Hola!'));
  });

  test('returns null when there is nothing to restore', () {
    expect(buildConversationSeed(const []), isNull);
    expect(
      buildConversationSeed(
        [
          VoiceClientActionEvent('send_message', details: const {'text': 'x'}),
        ],
        pendingTexts: const ['x'],
      ),
      isNull,
    );
  });

  test('long transcripts are truncated from the front', () {
    final events = <VoiceEvent>[
      for (var i = 0; i < 200; i++) ...[
        VoiceUserTranscriptDelta('Mensaje número $i con contenido largo.'),
        VoiceAgentTranscriptDelta('Respuesta número $i con contenido largo.'),
        VoiceAgentTurnComplete(),
      ],
    ];
    final seed = buildConversationSeed(events, maxChars: 2000)!;

    expect(seed.length, lessThan(2600));
    expect(seed, contains('recent part of the conversation'));
    expect(seed, contains('Respuesta número 199'));
    expect(seed, isNot(contains('Mensaje número 0 ')));
  });
}
