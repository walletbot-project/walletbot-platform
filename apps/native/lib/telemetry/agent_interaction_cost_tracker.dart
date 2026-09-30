import '../data/ids.dart';

class AgentInteractionCostSample {
  const AgentInteractionCostSample({
    required this.sampleId,
    required this.interactionType,
    required this.costUsd,
    required this.tokenAttributes,
  });

  final String sampleId;
  final String interactionType;
  final double costUsd;
  final Map<String, int> tokenAttributes;
}

class AgentUsageTotal {
  double costUsd = 0;
  final Map<String, int> tokens = {};
}

class AgentInteractionCostTracker {
  final Map<String, AgentUsageTotal> totalsByModel = {};
  bool _toolCallSinceLastUsage = false;

  void markToolCall() => _toolCallSinceLastUsage = true;

  /// Live usage describes one generation, not cumulative session totals.
  AgentInteractionCostSample? nextSample({
    required String sessionId,
    required String model,
    required double generationCostUsd,
    required String fallbackInteractionType,
    required Map<String, int> tokenAttributes,
  }) {
    final interactionType = _toolCallSinceLastUsage
        ? 'tool'
        : fallbackInteractionType;
    _toolCallSinceLastUsage = false;
    if (!generationCostUsd.isFinite || generationCostUsd <= 0) return null;
    final total = totalsByModel.putIfAbsent(model, AgentUsageTotal.new);
    total.costUsd += generationCostUsd;
    for (final entry in tokenAttributes.entries) {
      total.tokens.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    return AgentInteractionCostSample(
      sampleId: '$sessionId:${newUuid()}',
      interactionType: interactionType,
      costUsd: generationCostUsd,
      tokenAttributes: Map.of(tokenAttributes),
    );
  }
}
