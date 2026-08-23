import 'dart:convert';

import 'package:app/telemetry/agent_metrics.dart';
import 'package:app/telemetry/telemetry_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('estimates and sends session cost from usage metadata', () async {
    FlutterSecureStorage.setMockInitialValues({});

    http.Request? captured;
    final telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      sessionId: 'app-session-1',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );
    final metrics = AgentMetrics(telemetry);

    final costUsd = await metrics.recordSessionCostFromUsage(
      sessionId: 'voice-session-1',
      model: 'gemini-3.1-flash-live-preview',
      mode: 'text',
      usage: {
        'promptTokenCount': 1000,
        'responseTokenCount': 1000,
        'promptTokensDetails': [
          {'modality': 'TEXT', 'tokenCount': 1000},
        ],
        'responseTokensDetails': [
          {'modality': 'TEXT', 'tokenCount': 1000},
        ],
      },
    );

    expect(costUsd, closeTo(0.00525, 0.000001));
    expect(
      captured?.url.toString(),
      'https://example.convex.site/telemetry/metrics',
    );

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final sent = body['metrics'] as List<Object?>;
    expect(sent, hasLength(1));

    final costMetric = sent.first as Map<String, Object?>;
    expect(costMetric['name'], 'agent.session.cost_usd');
    expect(costMetric['type'], 'gauge');
    expect(costMetric['unit'], 'usd');
    expect(costMetric['value'], closeTo(0.00525, 0.000001));
    expect(costMetric['sessionId'], 'voice-session-1');
    expect(costMetric['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'mode': 'text',
      'cost_source': 'estimated',
      'token_input_text': 1000,
      'token_output_text': 1000,
    });

    telemetry.dispose();
  });

  test('estimates final session cost from total token count only', () {
    final metrics = AgentMetrics(null);

    final costUsd = metrics.estimateSessionCostUsd({'totalTokenCount': 1000});

    expect(costUsd, closeTo(0.0045, 0.000001));
  });

  test('sends interaction cost gauge from total token count only', () async {
    FlutterSecureStorage.setMockInitialValues({});

    http.Request? captured;
    final telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );
    final metrics = AgentMetrics(telemetry);

    final costUsd = await metrics.recordInteractionCostFromUsage(
      sessionId: 'voice-session-3',
      sampleId: 'voice-session-3:1',
      model: 'gemini-3.1-flash-live-preview',
      mode: 'text',
      interactionType: 'text',
      usage: {'totalTokenCount': 1000},
    );

    expect(costUsd, closeTo(0.0045, 0.000001));

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final sent = body['metrics'] as List<Object?>;
    expect(sent, hasLength(2));

    final costMetric = sent[0] as Map<String, Object?>;
    expect(costMetric['name'], 'agent.interaction.cost_usd');
    expect(costMetric['type'], 'gauge');
    expect(costMetric['unit'], 'usd');
    expect(costMetric['value'], closeTo(0.0045, 0.000001));
    expect(costMetric['sessionId'], 'voice-session-3');
    expect(costMetric['sampleId'], 'voice-session-3:1');
    expect(costMetric['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'mode': 'text',
      'cost_source': 'estimated',
      'token_output_text': 1000,
      'token_total': 1000,
    });

    final interactionMetric = sent[1] as Map<String, Object?>;
    expect(interactionMetric['name'], 'agent.interactions.completed_count');
    expect(interactionMetric['type'], 'counter');
    expect(interactionMetric['unit'], 'count');
    expect(interactionMetric['value'], 1);
    expect(interactionMetric['sessionId'], 'voice-session-3');
    expect(interactionMetric['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'mode': 'text',
      'interaction_type': 'text',
    });

    telemetry.dispose();
  });
}
