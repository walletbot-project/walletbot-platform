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

class AgentInteractionCostTracker {
  double? _lastTotalCostUsd;
  Map<String, int>? _lastTokenAttributes;
  bool _toolCallSinceLastUsage = false;

  void markToolCall() {
    _toolCallSinceLastUsage = true;
  }

  AgentInteractionCostSample? nextSample({
    required String sessionId,
    required double totalCostUsd,
    required String fallbackInteractionType,
    required Map<String, int> tokenAttributes,
  }) {
    final interactionType = _toolCallSinceLastUsage
        ? 'tool'
        : fallbackInteractionType;
    _toolCallSinceLastUsage = false;

    final previousTotalCostUsd = _lastTotalCostUsd;
    if (totalCostUsd == previousTotalCostUsd) return null;

    final previousTokenAttributes = _lastTokenAttributes;
    final interactionCostUsd =
        previousTotalCostUsd == null || totalCostUsd < previousTotalCostUsd
        ? totalCostUsd
        : totalCostUsd - previousTotalCostUsd;
    _lastTotalCostUsd = totalCostUsd;
    _lastTokenAttributes = tokenAttributes;
    if (interactionCostUsd <= 0) return null;

    return AgentInteractionCostSample(
      sampleId: '$sessionId:${newUuid()}',
      interactionType: interactionType,
      costUsd: interactionCostUsd,
      tokenAttributes: _deltaTokenAttributes(
        tokenAttributes,
        previousTokenAttributes,
      ),
    );
  }

  Map<String, int> _deltaTokenAttributes(
    Map<String, int> current,
    Map<String, int>? previous,
  ) {
    if (previous == null) return current;
    final delta = <String, int>{};
    for (final entry in current.entries) {
      final value = entry.value - (previous[entry.key] ?? 0);
      if (value > 0) delta[entry.key] = value;
    }
    return delta;
  }
}
