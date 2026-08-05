import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:app/main.dart';
import 'package:app/settings/display_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/memory_display_settings_store.dart';

const _testClientInfo = ClientInfo(
  platform: 'unknown',
  appVersion: '0.0.0',
  deviceId: 'test-device',
);

// Only error/pending paths are exercised — success paths reach
// ConvexClient, which cannot initialize under `flutter test`.
void main() {
  setUpAll(() {
    AppConfig.setRuntimeUrls(
      backendUrl: 'https://backend.test',
      siteUrl: 'https://site.test',
    );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpLogin(WidgetTester tester, AuthController auth) async {
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
  }

  Future<void> drainResendCooldown(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 31));
  }

  testWidgets('sign-up blocked by verification shows the pending panel', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final auth = AuthController(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'code': 'email_not_verified', 'message': 'verify'}),
          403,
        );
      }),
    );
    await pumpLogin(tester, auth);

    await tester.tap(find.text('¿Necesitás una cuenta? Registrate'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@test.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();

    expect(requests.single.url.path, '/auth/email/sign-up');
    expect(find.text('Verificá tu correo'), findsOneWidget);
    expect(find.text('Ya verifiqué — iniciar sesión'), findsOneWidget);
    // Cooldown just started: the resend button shows the countdown, disabled.
    expect(find.textContaining('Reenviar en'), findsOneWidget);
    expect(auth.accounts, isEmpty);

    await drainResendCooldown(tester);
    expect(find.text('Reenviar correo'), findsOneWidget);
  });

  testWidgets('premature "I verified" sign-in returns to pending with notice', (
    tester,
  ) async {
    final auth = AuthController(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'email_not_verified', 'message': 'verify'}),
          403,
        ),
      ),
    );
    await pumpLogin(tester, auth);

    // Reach the pending panel via a blocked sign-in.
    await tester.enterText(find.byType(TextFormField).at(0), 'ana@test.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Iniciar sesión').last);
    await tester.pumpAndSettle();
    expect(find.text('Verificá tu correo'), findsOneWidget);

    // "I verified" returns to the credentials form, email prefilled.
    await drainResendCooldown(tester);
    await tester.tap(find.text('Ya verifiqué — iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('ana@test.com'), findsOneWidget);

    // Signing in again while still unverified lands back on pending + notice.
    await tester.tap(find.text('Iniciar sesión').last);
    await tester.pumpAndSettle();
    expect(find.text('Verificá tu correo'), findsOneWidget);
    expect(
      find.text('Ese correo todavía no está verificado. '
          'Te enviamos un enlace nuevo.'),
      findsOneWidget,
    );

    await drainResendCooldown(tester);
  });

  testWidgets('forgot password requests the reset email and shows sent state', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final auth = AuthController(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    await pumpLogin(tester, auth);

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@test.com');
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    // Email carried over from the sign-in form.
    expect(find.text('ana@test.com'), findsOneWidget);

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    final request = requests.single;
    expect(request.url.path, '/auth/password/forgot');
    expect(jsonDecode(request.body), {'email': 'ana@test.com'});
    expect(
      find.textContaining('le enviamos un enlace para restablecer'),
      findsOneWidget,
    );

    // Back to sign in keeps the email around.
    await tester.tap(find.text('Volver a iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('ana@test.com'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });
}
