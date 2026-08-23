import 'package:app/telemetry/agent_interaction_cost_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts cumulative totals to interaction deltas', () {
    final tracker = AgentInteractionCostTracker();

    final first = tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.10,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 100},
    );
    final second = tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.25,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 250},
    );

    expect(first?.costUsd, closeTo(0.10, 0.000001));
    expect(second?.costUsd, closeTo(0.15, 0.000001));
    expect(first?.tokenAttributes, {'token_input_text': 100});
    expect(second?.tokenAttributes, {'token_input_text': 150});
  });

  test('does not emit duplicate unchanged totals', () {
    final tracker = AgentInteractionCostTracker();

    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        totalCostUsd: 0.10,
        fallbackInteractionType: 'text',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNotNull,
    );
    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        totalCostUsd: 0.10,
        fallbackInteractionType: 'text',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNull,
    );
  });

  test('uses unique sample ids for the same session', () {
    final tracker = AgentInteractionCostTracker();

    final first = tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.10,
      fallbackInteractionType: 'text',
      tokenAttributes: {'token_input_text': 100},
    );
    final second = tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.20,
      fallbackInteractionType: 'text',
      tokenAttributes: {'token_input_text': 200},
    );

    expect(first?.sampleId, startsWith('session-1:'));
    expect(second?.sampleId, startsWith('session-1:'));
    expect(first?.sampleId, isNot(second?.sampleId));
  });

  test('tool marker is consumed even when a sample is not emitted', () {
    final tracker = AgentInteractionCostTracker();

    tracker.markToolCall();
    tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.10,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 100},
    );

    tracker.markToolCall();
    expect(
      tracker.nextSample(
        sessionId: 'session-1',
        totalCostUsd: 0.10,
        fallbackInteractionType: 'voice',
        tokenAttributes: {'token_input_text': 100},
      ),
      isNull,
    );

    final next = tracker.nextSample(
      sessionId: 'session-1',
      totalCostUsd: 0.20,
      fallbackInteractionType: 'voice',
      tokenAttributes: {'token_input_text': 200},
    );

    expect(next?.interactionType, 'voice');
  });
}
