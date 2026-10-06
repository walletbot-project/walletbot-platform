import 'dart:convert';
import 'package:app/voice/live_protocol.dart';
import 'package:app/voice/live_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<LiveToken> fetch(Object? model) => http.runWithClient(
  () => fetchLiveToken(
    useAuthenticatedTokenAction: false,
    convexClient: null,
    sessionToken: null,
    deviceId: 'test-device',
    convexSiteUrl: 'https://test.invalid',
  ),
  () => MockClient(
    (_) async => http.Response(
      jsonEncode({'token': 'auth_tokens/test', 'model': model}),
      200,
    ),
  ),
);

void main() {
  for (final model in ['gemini-3.8-live', LiveToken.legacyModel]) {
    test('keeps the token paired with $model', () async {
      final token = await fetch(model);
      expect(token.token, 'auth_tokens/test');
      expect(token.model, model);
      expect(
        LiveProtocol.setup(model: token.model)['setup']['model'],
        'models/$model',
      );
    });
  }
  test(
    'failed context building preserves local identity and accepts the legacy model',
    () async {
      final token = await http.runWithClient(
        () => fetchLiveToken(
          useAuthenticatedTokenAction: false,
          convexClient: null,
          sessionToken: null,
          deviceId: 'test-device',
          localAccountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          convexSiteUrl: 'https://test.invalid',
          buildMintArgs: () async => throw StateError('context unavailable'),
        ),
        () => MockClient((request) async {
          expect(jsonDecode(request.body), {
            'deviceId': 'test-device',
            'localAccountId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          });
          return http.Response(
            jsonEncode({
              'token': 'auth_tokens/test',
              'model': LiveToken.legacyModel,
            }),
            200,
          );
        }),
      );
      expect(token.model, LiveToken.legacyModel);
    },
  );
  for (final model in [null, 'unknown-model', 42]) {
    test('rejects a missing or unsupported token model: $model', () async {
      await expectLater(
        fetch(model),
        throwsA(isA<LiveTokenRefusedException>()),
      );
    });
  }
}
