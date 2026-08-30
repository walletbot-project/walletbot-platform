import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/main.dart';
import 'package:app/settings/display_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/memory_display_settings_store.dart';

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

    // No ConvexClient is wired: a freshly constructed (empty) controller is
    // equivalent to load() with empty storage, and auth attach/detach are
    // no-ops without a client.
    final auth = AuthController();

    // AppConfigController is constructed but never loaded here (no network);
    // banner state stays empty.
    await tester.pumpWidget(
      MyApp(
        auth: auth,
        displaySettings: DisplaySettingsController(
          store: MemoryDisplaySettingsStore(),
        ),
        appConfig: AppConfigController(),
        clientInfo: _testClientInfo,
        locale: const Locale('es'),
      ),
    );
    await tester.pump();

    expect(find.text('Cuenta local'), findsWidgets);
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
        displaySettings: DisplaySettingsController(
          store: MemoryDisplaySettingsStore(),
        ),
        appConfig: AppConfigController(),
        clientInfo: _testClientInfo,
        locale: const Locale('es'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Cuenta local').first);
    await tester.pumpAndSettle();

    expect(find.text('Nombre'), findsOneWidget);

    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pump();

    expect(find.text('Ingresá un nombre'), findsOneWidget);
    expect(auth.activeAccount, isNull);
  });

  testWidgets('renders the login flow in English', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthController();
    await tester.pumpWidget(
      MyApp(
        auth: auth,
        displaySettings: DisplaySettingsController(
          store: MemoryDisplaySettingsStore(),
        ),
        appConfig: AppConfigController(),
        clientInfo: _testClientInfo,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('Local account'), findsWidgets);
    await tester.tap(find.text('Local account').first);
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Continue locally'), findsOneWidget);
  });
}
