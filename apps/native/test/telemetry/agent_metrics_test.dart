import 'dart:convert';

import 'package:app/telemetry/agent_metrics.dart';
import 'package:app/telemetry/telemetry_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final model in ['gemini-3.8-live', 'gemini-3.1-flash-live-preview']) {
    test('HTTP metric payloads preserve selected model $model', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sent = <Map<String, dynamic>>[];
      final telemetry = TelemetryClient(
        convexSiteUrl: 'https://example.convex.site',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          sent.addAll((body['metrics'] as List).cast<Map<String, dynamic>>());
          return http.Response('{"accepted":1}', 200);
        }),
      );
      final metrics = AgentMetrics(telemetry);
      const usage = <String, Object?>{
        'promptTokenCount': 100,
        'responseTokenCount': 50,
      };
      await metrics.recordInteractionCostFromUsage(
        sessionId: 'voice-test',
        sampleId: 'voice-test:1',
        model: model,
        mode: 'voice',
        interactionType: 'voice',
        usage: usage,
      );
      await metrics.recordSessionCostFromUsage(
        sessionId: 'voice-test',
        model: model,
        mode: 'voice',
        usage: usage,
      );
      expect(sent.map((metric) => metric['name']), [
        'agent.interaction.cost_usd',
        'agent.interactions.completed_count',
        'agent.session.cost_usd',
      ]);
      for (final metric in sent) {
        expect(metric['attributes']['model'], model);
        expect(metric['sessionId'], 'voice-test');
      }
      telemetry.dispose();
    });
  }

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

  test('counts an opened session apart from a resumed one', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final bodies = <String>[];
    final telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      sessionId: 'app-session-2',
      httpClient: MockClient((request) async {
        bodies.add(request.body);
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );
    final metrics = AgentMetrics(telemetry);

    await metrics.recordSessionStarted(
      sessionId: 'voice-session-4',
      model: 'gemini-3.1-flash-live-preview',
      resumed: false,
    );
    await metrics.recordSessionStarted(
      sessionId: 'voice-session-4',
      model: 'gemini-3.1-flash-live-preview',
      resumed: true,
    );

    expect(bodies, hasLength(2));

    Map<String, Object?> onlyMetric(String body) {
      final sent =
          (jsonDecode(body) as Map<String, Object?>)['metrics']
              as List<Object?>;
      expect(sent, hasLength(1));
      return sent.single as Map<String, Object?>;
    }

    final started = onlyMetric(bodies[0]);
    expect(started['name'], 'agent.sessions.started_count');
    expect(started['type'], 'counter');
    expect(started['unit'], 'count');
    expect(started['value'], 1);
    expect(started['sessionId'], 'voice-session-4');
    expect(started['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'start_kind': 'new',
    });

    expect(onlyMetric(bodies[1])['attributes'], {
      'model': 'gemini-3.1-flash-live-preview',
      'start_kind': 'resumed',
    });

    telemetry.dispose();
  });

  test(
    'sends time to first response as raw milliseconds, not a bucket',
    () async {
      FlutterSecureStorage.setMockInitialValues({});

      final bodies = <String>[];
      final telemetry = TelemetryClient(
        convexSiteUrl: 'https://example.convex.site',
        httpClient: MockClient((request) async {
          bodies.add(request.body);
          return http.Response('{"ok":true,"accepted":1}', 200);
        }),
      );
      final metrics = AgentMetrics(telemetry);

      await metrics.recordFirstResponse(elapsedMs: 1830, mode: 'text');
      await metrics.recordFirstResponse(elapsedMs: 420, mode: 'voice');
      // Anything that is not 'text' is a voice turn.
      await metrics.recordFirstResponse(elapsedMs: 7, mode: 'other');

      final sent = [
        for (final body in bodies)
          ...((jsonDecode(body) as Map<String, Object?>)['metrics']
                  as List<Object?>)
              .cast<Map<String, Object?>>(),
      ];
      expect(sent, hasLength(3));
      for (final metric in sent) {
        expect(metric['name'], 'agent.response.first_token_ms');
        expect(metric['type'], 'gauge');
        expect(metric['unit'], 'ms');
      }
      expect(sent.map((m) => m['value']), [1830, 420, 7]);
      expect(sent.map((m) => m['attributes']), [
        {'mode': 'text', 'platform': currentPlatform},
        {'mode': 'voice', 'platform': currentPlatform},
        {'mode': 'voice', 'platform': currentPlatform},
      ]);
      expect(
        sent.where(
          (m) => m['name'] == 'agent.response.first_token_bucket_count',
        ),
        isEmpty,
        reason: 'the backend derives the bucket counter from the gauge',
      );

      telemetry.dispose();
    },
  );

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
