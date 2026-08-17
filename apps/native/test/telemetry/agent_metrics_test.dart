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
        return http.Response('{"ok":true,"accepted":2}', 200);
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
    expect(sent, hasLength(2));

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
    });

    final bucketMetric = sent[1] as Map<String, Object?>;
    expect(bucketMetric['name'], 'agent.session.cost_bucket_count');
    expect(bucketMetric['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'mode': 'text',
      'cost_bucket': '0-0.01',
    });

    telemetry.dispose();
  });

  test('sends outlier counters for exceeded cost thresholds', () async {
    FlutterSecureStorage.setMockInitialValues({});

    http.Request? captured;
    final telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"accepted":5}', 200);
      }),
    );
    final metrics = AgentMetrics(telemetry);

    await metrics.recordSessionCostFromUsage(
      sessionId: 'voice-session-2',
      model: 'gemini-3.1-flash-live-preview',
      mode: 'voice',
      usage: {
        'responseTokenCount': 10000,
        'responseTokensDetails': [
          {'modality': 'AUDIO', 'tokenCount': 10000},
        ],
      },
    );

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final sent = (body['metrics'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(sent, hasLength(5));
    expect(
      sent
          .where(
            (metric) => metric['name'] == 'agent.session.cost_outlier_count',
          )
          .map((metric) => metric['attributes'] as Map<String, Object?>)
          .map((attributes) => attributes['threshold_usd']),
      ['0.01', '0.05', '0.10'],
    );
    expect(
      sent.singleWhere(
        (metric) => metric['name'] == 'agent.session.cost_bucket_count',
      )['attributes'],
      {
        'model': 'gemini-3.1-flash-live-preview',
        'mode': 'voice',
        'cost_bucket': '0.10-0.50',
      },
    );

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
    expect(costMetric['name'], 'agent.session.cost_usd');
    expect(costMetric['type'], 'gauge');
    expect(costMetric['unit'], 'usd');
    expect(costMetric['value'], closeTo(0.0045, 0.000001));
    expect(costMetric['sessionId'], 'voice-session-3');
    expect(costMetric['sampleId'], 'voice-session-3:1');
    expect(costMetric['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'mode': 'text',
      'cost_source': 'estimated',
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
