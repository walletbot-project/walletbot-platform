import 'dart:async';

import 'telemetry_client.dart';

class AgentMetrics {
  const AgentMetrics(this._telemetry);

  // Gemini 3.1 Flash Live Preview paid-tier list prices per 1M tokens,
  // from Google AI pricing last updated 2026-07-21. Keep these values
  // conservative and mark emitted costs as estimated until provider billing
  // reconciliation is available.
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
        sessionId: sessionId,
        model: model,
        mode: normalizedMode,
        costUsd: costUsd,
      ),
      TelemetryMetric(
        name: 'agent.session.cost_bucket_count',
        timestamp: DateTime.now(),
        source: 'native',
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: {
          'model': model,
          'mode': normalizedMode,
          'cost_bucket': _costBucket(costUsd),
        },
        sessionId: sessionId,
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
  }) async {
    await _telemetry?.sendMetricBatch([
      _costGaugeMetric(
        sessionId: sessionId,
        sampleId: sampleId,
        model: model,
        mode: _normalizeMode(mode),
        costUsd: costUsd,
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
  }) {
    unawaited(
      recordInteractionCost(
        sessionId: sessionId,
        sampleId: sampleId,
        model: model,
        mode: mode,
        interactionType: interactionType,
        costUsd: costUsd,
      ),
    );
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
    required String sessionId,
    String? sampleId,
    required String model,
    required String mode,
    required double costUsd,
  }) => TelemetryMetric(
    name: 'agent.session.cost_usd',
    timestamp: DateTime.now(),
    source: 'native',
    type: 'gauge',
    value: costUsd,
    unit: 'usd',
    attributes: {'model': model, 'mode': mode, 'cost_source': 'estimated'},
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
    if (value is! List) return null;
    final details = <String, int>{};
    for (final item in value) {
      if (item is! Map) continue;
      final modality =
          item['modality']?.toString() ??
          item['modalityType']?.toString() ??
          'text';
      final tokens = _intValue(item['tokenCount']);
      if (tokens == null) continue;
      final normalized = modality.toLowerCase();
      details[normalized] = (details[normalized] ?? 0) + tokens;
    }
    return details;
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _normalizeMode(String mode) => switch (mode) {
    'voice' || 'text' || 'mixed' => mode,
    _ => 'mixed',
  };

  String _normalizeInteractionType(String value) => switch (value) {
    'voice' || 'text' || 'mixed' || 'tool' => value,
    _ => 'mixed',
  };

  String _costBucket(double costUsd) {
    if (costUsd < 0.01) return '0-0.01';
    if (costUsd < 0.05) return '0.01-0.05';
    if (costUsd < 0.10) return '0.05-0.10';
    if (costUsd < 0.50) return '0.10-0.50';
    if (costUsd < 1.00) return '0.50-1.00';
    return '1.00+';
  }
}
