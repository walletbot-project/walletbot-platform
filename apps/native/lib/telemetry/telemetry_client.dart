import 'dart:async';
import 'dart:convert';

import 'package:app/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

typedef AccessTokenProvider = Future<String?> Function();

class TelemetryClient {
  TelemetryClient({
    String? convexSiteUrl,
    http.Client? httpClient,
    FlutterSecureStorage? storage,
    AccessTokenProvider? accessTokenProvider,
    String? sessionId,
  }) : _convexSiteUrl = convexSiteUrl ?? AppConfig.convexSiteUrl,
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _storage = storage ?? const FlutterSecureStorage(),
       _accessTokenProvider = accessTokenProvider,
       sessionId = sessionId ?? const Uuid().v4();

  static const _installationIdKey = 'telemetry_installation_id';

  final String _convexSiteUrl;
  final http.Client _http;
  final bool _ownsHttpClient;
  final FlutterSecureStorage _storage;
  final AccessTokenProvider? _accessTokenProvider;
  final String sessionId;
  Future<String>? _installationIdFuture;

  Future<void> track(
    String name, {
    Map<String, Object?> properties = const {},
    DateTime? timestamp,
  }) {
    return sendBatch([
      TelemetryEvent(
        name: name,
        timestamp: timestamp ?? DateTime.now(),
        properties: properties,
      ),
    ]);
  }

  Future<void> trackMetric(
    String name, {
    required String type,
    required double value,
    String source = 'native',
    String? unit,
    Map<String, Object?> attributes = const {},
    DateTime? timestamp,
  }) {
    return sendMetricBatch([
      TelemetryMetric(
        name: name,
        timestamp: timestamp ?? DateTime.now(),
        source: source,
        type: type,
        value: value,
        unit: unit,
        attributes: attributes,
      ),
    ]);
  }

  Future<void> sendBatch(List<TelemetryEvent> events) async {
    if (events.isEmpty || _convexSiteUrl.isEmpty) return;

    try {
      final installationId = await _installationId();
      final accessToken = await _accessTokenProvider?.call();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }

      final response = await _http
          .post(
            Uri.parse('$_convexSiteUrl/telemetry/events'),
            headers: headers,
            body: jsonEncode({
              'events': events
                  .map(
                    (event) => event.toJson(
                      installationId: installationId,
                      sessionId: sessionId,
                      appVersion: AppConfig.appVersion,
                      platform: _platform,
                    ),
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('telemetry: HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (error) {
      debugPrint('telemetry: send failed: $error');
    }
  }

  Future<void> sendMetricBatch(List<TelemetryMetric> metrics) async {
    if (metrics.isEmpty || _convexSiteUrl.isEmpty) return;

    try {
      final installationId = await _installationId();
      final accessToken = await _accessTokenProvider?.call();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }

      final response = await _http
          .post(
            Uri.parse('$_convexSiteUrl/telemetry/metrics'),
            headers: headers,
            body: jsonEncode({
              'metrics': metrics
                  .map(
                    (metric) => metric.toJson(
                      installationId: installationId,
                      sessionId: sessionId,
                      appVersion: AppConfig.appVersion,
                      platform: _platform,
                    ),
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'telemetry metrics: HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('telemetry metrics: send failed: $error');
    }
  }

  Future<String> _installationId() {
    return _installationIdFuture ??= () async {
      final existing = await _storage.read(key: _installationIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final created = const Uuid().v4();
      await _storage.write(key: _installationIdKey, value: created);
      return created;
    }();
  }

  void dispose() {
    if (_ownsHttpClient) _http.close();
  }
}

class TelemetryEvent {
  const TelemetryEvent({
    required this.name,
    required this.timestamp,
    this.properties = const {},
  });

  final String name;
  final DateTime timestamp;
  final Map<String, Object?> properties;

  Map<String, Object?> toJson({
    required String installationId,
    required String sessionId,
    required String appVersion,
    required String platform,
  }) => {
    'name': name,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'properties': properties,
    'installationId': installationId,
    'sessionId': sessionId,
    'appVersion': appVersion,
    'platform': platform,
  };
}

class TelemetryMetric {
  const TelemetryMetric({
    required this.name,
    required this.timestamp,
    required this.source,
    required this.type,
    required this.value,
    this.unit,
    this.attributes = const {},
  });

  final String name;
  final DateTime timestamp;
  final String source;
  final String type;
  final double value;
  final String? unit;
  final Map<String, Object?> attributes;

  Map<String, Object?> toJson({
    required String installationId,
    required String sessionId,
    required String appVersion,
    required String platform,
  }) => {
    'name': name,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'source': source,
    'type': type,
    'value': value,
    if (unit != null) 'unit': unit,
    'attributes': attributes,
    'installationId': installationId,
    'sessionId': sessionId,
    'appVersion': appVersion,
    'platform': platform,
  };
}

String get _platform {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'linux';
  }
}
