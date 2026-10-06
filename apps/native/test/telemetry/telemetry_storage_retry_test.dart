import 'dart:async';
import 'dart:convert';

import 'package:app/telemetry/telemetry_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class RecoveringStorage extends FlutterSecureStorage {
  RecoveringStorage({this.failRead = false, this.failWrite = false});
  bool failRead;
  bool failWrite;
  int reads = 0;
  int writes = 0;
  String? saved;
  Completer<void>? readGate;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    await readGate?.future;
    if (failRead) {
      failRead = false;
      throw StateError('temporary read failure');
    }
    return saved;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    if (failWrite) {
      failWrite = false;
      throw StateError('temporary write failure');
    }
    saved = value;
  }
}

void main() {
  final metric = TelemetryMetric(
    name: 'agent.interaction.cost_usd',
    timestamp: DateTime(2026),
    source: 'native',
    type: 'gauge',
    value: 1,
    appUserId: 'local:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  );
  for (final failure in ['read', 'write']) {
    test(
      'retries after a storage $failure failure and caches only the successful ID',
      () async {
        final storage = RecoveringStorage(
          failRead: failure == 'read',
          failWrite: failure == 'write',
        );
        final sent = <String>[];
        final client = TelemetryClient(
          convexSiteUrl: 'https://test.invalid',
          storage: storage,
          httpClient: MockClient((request) async {
            sent.add(
              (jsonDecode(request.body)['metrics'][0]['installationId'])
                  as String,
            );
            return http.Response('{}', 200);
          }),
        );
        await client.sendMetricBatch([metric]);
        expect(sent, isEmpty);
        await client.sendMetricBatch([metric]);
        await client.sendMetricBatch([metric]);
        expect(storage.reads, 2);
        expect(sent, [storage.saved, storage.saved]);
        client.dispose();
      },
    );
  }
  test(
    'concurrent sends share one storage attempt and one persisted identity',
    () async {
      final gate = Completer<void>();
      final storage = RecoveringStorage()..readGate = gate;
      final sent = <String>[];
      final client = TelemetryClient(
        convexSiteUrl: 'https://test.invalid',
        storage: storage,
        httpClient: MockClient((request) async {
          sent.add(
            (jsonDecode(request.body)['metrics'][0]['installationId'])
                as String,
          );
          return http.Response('{}', 200);
        }),
      );
      final first = client.sendMetricBatch([metric]);
      final second = client.sendMetricBatch([metric]);
      expect(storage.reads, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(storage.writes, 1);
      expect(sent, [storage.saved, storage.saved]);
      client.dispose();
    },
  );
}
