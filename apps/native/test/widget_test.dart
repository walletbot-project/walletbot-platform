import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _testClientInfo = ClientInfo(
  platform: 'unknown',
  appVersion: '0.0.0',
  deviceId: 'test-device',
);

void main() {
  testWidgets('shows login when no account is active', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthController();
    // Note: production startup runs ConvexClient.initialize() before
    // auth.load(), and load() touches ConvexClient unconditionally
    // (_detachAuth -> setAuth). The native client can't be initialized in
    // widget tests, so we render with a freshly constructed (empty)
    // controller, which is equivalent to load() with empty storage.

    // AppConfigController is constructed but never loaded here (no network);
    // banner state stays empty.
    await tester.pumpWidget(
      MyApp(
        auth: auth,
        appConfig: AppConfigController(),
        clientInfo: _testClientInfo,
      ),
    );
    await tester.pump();

    expect(find.text('Sin cuenta'), findsWidgets);
  });

  testWidgets('requires a name before continuing without an account', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthController();

    // AppConfigController is constructed but never loaded here (no network);
    // banner state stays empty.
    await tester.pumpWidget(
      MyApp(
        auth: auth,
        appConfig: AppConfigController(),
        clientInfo: _testClientInfo,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Sin cuenta').first);
    await tester.pumpAndSettle();

    expect(find.text('Nombre'), findsOneWidget);

    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pump();

    expect(find.text('Ingresá un nombre'), findsOneWidget);
    expect(auth.activeAccount, isNull);
  });
}
