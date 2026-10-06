import 'package:app/telemetry/agent_interaction_cost_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps each generation in full and accumulates session totals', () {
    final tracker = AgentInteractionCostTracker();

    final first = tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.10,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 100},
    );
    final second = tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.25,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 250},
    );

    expect(first?.costUsd, closeTo(0.10, 0.000001));
    expect(second?.costUsd, closeTo(0.25, 0.000001));
    expect(first?.tokenAttributes, {'token_input_text': 100});
    expect(second?.tokenAttributes, {'token_input_text': 250});
  });

  test('keeps distinct generations with equal cost', () {
    final tracker = AgentInteractionCostTracker();

    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        model: 'gemini-3.8-live',
        generationCostUsd: 0.10,
        fallbackInteractionType: 'text',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNotNull,
    );
    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        model: 'gemini-3.8-live',
        generationCostUsd: 0.10,
        fallbackInteractionType: 'text',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNotNull,
    );
  });

  test(
    'a smaller generation after model rollback retains tokens and separate totals',
    () {
      final tracker = AgentInteractionCostTracker();
      for (final model in [
        'gemini-3.8-live',
        'gemini-3.1-flash-live-preview',
      ]) {
        for (final count in [100, 100, 50]) {
          final sample = tracker.nextSample(
            sessionId: 's',
            model: model,
            generationCostUsd: count / 1000,
            fallbackInteractionType: 'text',
            tokenAttributes: {'token_input_text': count},
          );
          expect(sample?.tokenAttributes, {'token_input_text': count});
        }
        expect(tracker.totalsByModel[model]?.tokens, {'token_input_text': 250});
        expect(tracker.totalsByModel[model]?.costUsd, closeTo(0.25, 0.000001));
      }
      expect(tracker.totalsByModel, hasLength(2));
    },
  );

  test('uses unique sample ids for the same session', () {
    final tracker = AgentInteractionCostTracker();

    final first = tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.10,
      fallbackInteractionType: 'text',
      tokenAttributes: {'token_input_text': 100},
    );
    final second = tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.20,
      fallbackInteractionType: 'text',
      tokenAttributes: {'token_input_text': 200},
    );

    expect(first?.sampleId, startsWith('session-1:'));
    expect(second?.sampleId, startsWith('session-1:'));
    expect(first?.sampleId, isNot(second?.sampleId));
  });

  test('tool marker is consumed even when an empty sample is not emitted', () {
    final tracker = AgentInteractionCostTracker();

    tracker.markToolCall();
    tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.10,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 100},
    );

    tracker.markToolCall();
    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        model: 'gemini-3.8-live',
        generationCostUsd: 0,
        fallbackInteractionType: 'voice',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNull,
    );

    final next = tracker.nextSample(
      sessionId: 'session-1',
      model: 'gemini-3.8-live',
      generationCostUsd: 0.20,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 200},
    );

    expect(next?.interactionType, 'voice');
  });
}
