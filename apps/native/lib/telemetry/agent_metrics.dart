import 'dart:async';

import 'telemetry_client.dart';

class AgentMetrics {
  const AgentMetrics(this._telemetry);

  // Local estimate only used for client-side delta detection. Backend pricing
  // recalculates USD from token attributes before storing/exporting metrics.
  static const _gemini31FlashLiveInputTextUsdPerMillion = 0.75;
  static const _gemini31FlashLiveInputAudioUsdPerMillion = 3.00;
  static const _gemini31FlashLiveInputMediaUsdPerMillion = 1.00;
  static const _gemini31FlashLiveOutputTextUsdPerMillion = 4.50;
  static const _gemini31FlashLiveOutputAudioUsdPerMillion = 12.00;
  final TelemetryClient? _telemetry;

  Future<double?> recordSessionCostFromUsage({
    required String sessionId,
    required String model,
    required String mode,
    required Map<String, Object?> usage,
  }) async {
    final costUsd = estimateSessionCostUsd(usage);
    if (costUsd == null) return null;

    final normalizedMode = _normalizeMode(mode);
    final metrics = <TelemetryMetric>[
      _costGaugeMetric(
        name: 'agent.session.cost_usd',
        sessionId: sessionId,
        model: model,
        mode: normalizedMode,
        costUsd: costUsd,
        tokenAttributes: usageTokenAttributes(usage),
      ),
    ];

    await _telemetry?.sendMetricBatch(metrics);
    return costUsd;
  }

  Future<double?> recordInteractionCostFromUsage({
    required String sessionId,
    required String sampleId,
    required String model,
    required String mode,
    required String interactionType,
    required Map<String, Object?> usage,
  }) async {
    final costUsd = estimateSessionCostUsd(usage);
    if (costUsd == null) return null;

    await recordInteractionCost(
      sessionId: sessionId,
      sampleId: sampleId,
      model: model,
      mode: mode,
      interactionType: interactionType,
      costUsd: costUsd,
      tokenAttributes: usageTokenAttributes(usage),
    );
    return costUsd;
  }

  Future<void> recordInteractionCost({
    required String sessionId,
    required String sampleId,
    required String model,
    required String mode,
    required String interactionType,
    required double costUsd,
    Map<String, int> tokenAttributes = const {},
  }) async {
    await _telemetry?.sendMetricBatch([
      _costGaugeMetric(
        name: 'agent.interaction.cost_usd',
        sessionId: sessionId,
        sampleId: sampleId,
        model: model,
        mode: _normalizeMode(mode),
        costUsd: costUsd,
        tokenAttributes: tokenAttributes,
      ),
      TelemetryMetric(
        name: 'agent.interactions.completed_count',
        timestamp: DateTime.now(),
        source: 'native',
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: {
          'model': model,
          'mode': _normalizeMode(mode),
          'interaction_type': _normalizeInteractionType(interactionType),
        },
        sessionId: sessionId,
      ),
    ]);
  }

  void recordSessionCostFromUsageBestEffort({
    required String sessionId,
    required String model,
    required String mode,
    required Map<String, Object?> usage,
  }) {
    unawaited(
      recordSessionCostFromUsage(
        sessionId: sessionId,
        model: model,
        mode: mode,
        usage: usage,
      ),
    );
  }

  void recordInteractionCostFromUsageBestEffort({
    required String sessionId,
    required String sampleId,
    required String model,
    required String mode,
    required String interactionType,
    required Map<String, Object?> usage,
  }) {
    unawaited(
      recordInteractionCostFromUsage(
        sessionId: sessionId,
        sampleId: sampleId,
        model: model,
        mode: mode,
        interactionType: interactionType,
        usage: usage,
      ),
    );
  }

  void recordInteractionCostBestEffort({
    required String sessionId,
    required String sampleId,
    required String model,
    required String mode,
    required String interactionType,
    required double costUsd,
    Map<String, int> tokenAttributes = const {},
  }) {
    unawaited(
      recordInteractionCost(
        sessionId: sessionId,
        sampleId: sampleId,
        model: model,
        mode: mode,
        interactionType: interactionType,
        costUsd: costUsd,
        tokenAttributes: tokenAttributes,
      ),
    );
  }

  static Map<String, int> usageTokenAttributes(Map<String, Object?> usage) {
    final promptTokens = _staticIntValue(usage['promptTokenCount']);
    final responseTokens =
        _staticIntValue(usage['responseTokenCount']) ??
        _staticIntValue(usage['candidatesTokenCount']);
    final totalTokens = _staticIntValue(usage['totalTokenCount']);

    final promptDetails = _staticTokenDetails(usage['promptTokensDetails']);
    final responseDetails =
        _staticTokenDetails(usage['responseTokensDetails']) ??
        _staticTokenDetails(usage['candidatesTokensDetails']);

    final attributes = <String, int>{};
    _addTokenDetails(
      attributes,
      prefix: 'token_input',
      totalTokens: promptTokens,
      details: promptDetails,
    );
    _addTokenDetails(
      attributes,
      prefix: 'token_output',
      totalTokens: responseTokens,
      details: responseDetails,
    );
    _addPositive(
      attributes,
      'token_thinking',
      _staticIntValue(usage['thoughtsTokenCount']),
    );
    _addPositive(
      attributes,
      'token_tool_use_prompt',
      _staticIntValue(usage['toolUsePromptTokenCount']),
    );
    _addPositive(
      attributes,
      'token_cached_input',
      _staticIntValue(usage['cachedContentTokenCount']),
    );
    _addPositive(attributes, 'token_total', totalTokens);
    return attributes;
  }

  double? estimateSessionCostUsd(Map<String, Object?> usage) {
    final promptTokens = _intValue(usage['promptTokenCount']);
    final responseTokens =
        _intValue(usage['responseTokenCount']) ??
        _intValue(usage['candidatesTokenCount']);
    final totalTokens = _intValue(usage['totalTokenCount']);

    final promptDetails = _tokenDetails(usage['promptTokensDetails']);
    final responseDetails =
        _tokenDetails(usage['responseTokensDetails']) ??
        _tokenDetails(usage['candidatesTokensDetails']);

    final estimatedInputUsd = _estimateInputCost(
      totalTokens: promptTokens,
      details: promptDetails,
    );
    final estimatedOutputUsd = _estimateOutputCost(
      totalTokens: responseTokens,
      details: responseDetails,
    );

    if (estimatedInputUsd == null && estimatedOutputUsd == null) {
      if (totalTokens == null) return null;
      return _tokensToUsd(
        totalTokens,
        _gemini31FlashLiveOutputTextUsdPerMillion,
      );
    }
    return (estimatedInputUsd ?? 0) + (estimatedOutputUsd ?? 0);
  }

  TelemetryMetric _costGaugeMetric({
    required String name,
    required String sessionId,
    String? sampleId,
    required String model,
    required String mode,
    required double costUsd,
    required Map<String, int> tokenAttributes,
  }) => TelemetryMetric(
    name: name,
    timestamp: DateTime.now(),
    source: 'native',
    type: 'gauge',
    value: costUsd,
    unit: 'usd',
    attributes: {
      'model': model,
      'mode': mode,
      'cost_source': 'estimated',
      ...tokenAttributes,
    },
    sessionId: sessionId,
    sampleId: sampleId,
  );

  double? _estimateInputCost({
    required int? totalTokens,
    required Map<String, int>? details,
  }) => _estimateCost(
    totalTokens: totalTokens,
    details: details,
    textUsdPerMillion: _gemini31FlashLiveInputTextUsdPerMillion,
    audioUsdPerMillion: _gemini31FlashLiveInputAudioUsdPerMillion,
    mediaUsdPerMillion: _gemini31FlashLiveInputMediaUsdPerMillion,
  );

  double? _estimateOutputCost({
    required int? totalTokens,
    required Map<String, int>? details,
  }) => _estimateCost(
    totalTokens: totalTokens,
    details: details,
    textUsdPerMillion: _gemini31FlashLiveOutputTextUsdPerMillion,
    audioUsdPerMillion: _gemini31FlashLiveOutputAudioUsdPerMillion,
    mediaUsdPerMillion: _gemini31FlashLiveOutputTextUsdPerMillion,
  );

  double? _estimateCost({
    required int? totalTokens,
    required Map<String, int>? details,
    required double textUsdPerMillion,
    required double audioUsdPerMillion,
    required double mediaUsdPerMillion,
  }) {
    if (details == null || details.isEmpty) {
      if (totalTokens == null) return null;
      return _tokensToUsd(totalTokens, textUsdPerMillion);
    }

    var cost = 0.0;
    var detailedTokens = 0;
    for (final entry in details.entries) {
      final tokens = entry.value;
      detailedTokens += tokens;
      final price = switch (entry.key) {
        'audio' => audioUsdPerMillion,
        'image' || 'video' => mediaUsdPerMillion,
        _ => textUsdPerMillion,
      };
      cost += _tokensToUsd(tokens, price);
    }

    final remainder = totalTokens == null ? 0 : totalTokens - detailedTokens;
    if (remainder > 0) cost += _tokensToUsd(remainder, textUsdPerMillion);
    return cost;
  }

  double _tokensToUsd(int tokens, double usdPerMillion) =>
      tokens * usdPerMillion / 1000000;

  Map<String, int>? _tokenDetails(Object? value) {
    return _staticTokenDetails(value);
  }

  int? _intValue(Object? value) {
    return _staticIntValue(value);
  }

  static Map<String, int>? _staticTokenDetails(Object? value) {
    if (value is! List) return null;
    final details = <String, int>{};
    for (final item in value) {
      if (item is! Map) continue;
      final modality =
          item['modality']?.toString() ??
          item['modalityType']?.toString() ??
          'text';
      final tokens = _staticIntValue(item['tokenCount']);
      if (tokens == null) continue;
      final normalized = modality.toLowerCase();
      details[normalized] = (details[normalized] ?? 0) + tokens;
    }
    return details;
  }

  static int? _staticIntValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static void _addTokenDetails(
    Map<String, int> attributes, {
    required String prefix,
    required int? totalTokens,
    required Map<String, int>? details,
  }) {
    if (details == null || details.isEmpty) {
      _addPositive(attributes, '${prefix}_text', totalTokens);
      return;
    }

    var detailedTokens = 0;
    for (final entry in details.entries) {
      detailedTokens += entry.value;
      final suffix = switch (entry.key) {
        'audio' => 'audio',
        'image' || 'video' => 'media',
        _ => 'text',
      };
      attributes['${prefix}_$suffix'] =
          (attributes['${prefix}_$suffix'] ?? 0) + entry.value;
    }

    final remainder = totalTokens == null ? 0 : totalTokens - detailedTokens;
    _addPositive(attributes, '${prefix}_text', remainder);
  }

  static void _addPositive(
    Map<String, int> attributes,
    String key,
    int? value,
  ) {
    if (value == null || value <= 0) return;
    attributes[key] = (attributes[key] ?? 0) + value;
  }

  String _normalizeMode(String mode) => switch (mode) {
    'voice' || 'text' || 'mixed' => mode,
    _ => 'mixed',
  };

  String _normalizeInteractionType(String value) => switch (value) {
    'voice' || 'text' || 'mixed' || 'tool' => value,
    _ => 'mixed',
  };
}
