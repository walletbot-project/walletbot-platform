import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  ClientInfo clientInfo(String platform) =>
      ClientInfo(platform: platform, appVersion: '0.3.2', deviceId: 'device-1');

  AiConsentController controllerFor({
    String platform = 'ios',
    bool isRemote = true,
    ConvexClient? client,
  }) => AiConsentController(
    accountId: 'account-1',
    isRemote: isRemote,
    clientInfo: clientInfo(platform),
    locale: 'es-AR',
    client: client,
  );

  test('asks on iOS when nothing was stored', () async {
    final controller = controllerFor();
    await controller.load();

    expect(controller.isApplicable, isTrue);
    expect(controller.resolved, isTrue);
    expect(controller.accepted, isFalse);
  });

  test('never asks off iOS', () async {
    for (final platform in ['android', 'macos', 'unknown']) {
      final controller = controllerFor(platform: platform);
      await controller.load();

      expect(controller.isApplicable, isFalse, reason: platform);
      expect(controller.accepted, isTrue, reason: platform);
    }
  });

  test('a stored consent at the current version skips the sheet', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:account-1': aiConsentVersion,
    });
    final controller = controllerFor();
    await controller.load();

    expect(controller.accepted, isTrue);
  });

  test('a consent below the current version asks again', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:account-1': '2020-01-01',
    });
    final controller = controllerFor();
    await controller.load();

    expect(controller.accepted, isFalse);
  });

  test('accepting records the consent on the backend first', () async {
    final calls = <MapEntry<String, Map<String, Object?>>>[];
    final controller = controllerFor(
      client: _StubConvexClient((name, args) async {
        calls.add(MapEntry(name, args));
        return null;
      }),
    );
    await controller.load();

    await controller.accept();

    expect(calls.single.key, 'v1/legal/mutations:acceptAiConsent');
    expect(calls.single.value, {
      'platform': 'ios',
      'appVersion': '0.3.2',
      'locale': 'es-AR',
    });
    expect(controller.accepted, isTrue);
  });

  test('a failed backend write leaves the consent ungranted', () async {
    final controller = controllerFor(
      client: _StubConvexClient((_, _) async => throw StateError('offline')),
    );
    await controller.load();

    await expectLater(controller.accept(), throwsStateError);
    expect(controller.accepted, isFalse);
  });

  test('a local-only account records without a backend call', () async {
    var calls = 0;
    final controller = controllerFor(
      isRemote: false,
      client: _StubConvexClient((_, _) async {
        calls++;
        return null;
      }),
    );
    await controller.load();

    await controller.accept();

    expect(calls, 0);
    expect(controller.accepted, isTrue);
  });
}

class _StubConvexClient implements ConvexClient {
  _StubConvexClient(this.onMutation);

  final Future<Object?> Function(String name, Map<String, Object?> args)
  onMutation;

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async => await onMutation(name, args) as T;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
