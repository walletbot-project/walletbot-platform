import 'dart:convert';

import 'package:app/telemetry/telemetry_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends expected telemetry payload and auth header', () async {
    FlutterSecureStorage.setMockInitialValues({});

    http.Request? captured;
    final client = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      sessionId: 'session-1',
      accessTokenProvider: () async => 'access-token-1',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );

    await client.track(
      'screen.viewed',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1730000000000),
      properties: {'screen': 'home'},
    );

    expect(
      captured?.url.toString(),
      'https://example.convex.site/telemetry/events',
    );
    expect(captured?.headers['Authorization'], 'Bearer access-token-1');

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final events = body['events'] as List<Object?>;
    final event = events.single as Map<String, Object?>;
    expect(event['name'], 'screen.viewed');
    expect(event['timestamp'], 1730000000000);
    expect(event['sessionId'], 'session-1');
    expect(event['appVersion'], '1.0.0+1');
    expect(event['installationId'], isA<String>());
    expect(event['properties'], {'screen': 'home'});

    client.dispose();
  });

  test('keeps installationId stable across sends', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final installationIds = <String>[];
    final client = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      sessionId: 'session-1',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final events = body['events'] as List<Object?>;
        final event = events.single as Map<String, Object?>;
        installationIds.add(event['installationId'] as String);
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );

    await client.track('first');
    await client.track('second');

    expect(installationIds, hasLength(2));
    expect(installationIds.first, installationIds.last);

    client.dispose();
  });

  test('sends expected metric payload', () async {
    FlutterSecureStorage.setMockInitialValues({});

    http.Request? captured;
    final client = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      sessionId: 'session-1',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );

    await client.trackMetric(
      'business.movements.created_count',
      type: 'counter',
      value: 1,
      unit: 'count',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1730000000000),
      attributes: {
        'movement_type': 'expense',
        'created_by': 'form',
        'ingest_path': 'direct_client',
      },
    );

    expect(
      captured?.url.toString(),
      'https://example.convex.site/telemetry/metrics',
    );

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final metrics = body['metrics'] as List<Object?>;
    final metric = metrics.single as Map<String, Object?>;
    expect(metric['name'], 'business.movements.created_count');
    expect(metric['timestamp'], 1730000000000);
    expect(metric['source'], 'native');
    expect(metric['type'], 'counter');
    expect(metric['value'], 1);
    expect(metric['unit'], 'count');
    expect(metric['sessionId'], 'session-1');
    expect(metric['appVersion'], '1.0.0+1');
    expect(metric['installationId'], isA<String>());
    expect(metric['attributes'], {
      'movement_type': 'expense',
      'created_by': 'form',
      'ingest_path': 'direct_client',
    });

    client.dispose();
  });

  test('does not throw on HTTP error', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final client = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      httpClient: MockClient(
        (_) async => http.Response('{"code":"bad_request"}', 400),
      ),
    );

    await expectLater(client.track('screen.viewed'), completes);

    client.dispose();
  });
}
