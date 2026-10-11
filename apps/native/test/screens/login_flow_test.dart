import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/main.dart';
import 'package:app/screens/login.dart';
import 'package:app/settings/display_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_display_settings_store.dart';

const _testClientInfo = ClientInfo(
  platform: 'unknown',
  appVersion: '0.0.0',
  deviceId: 'test-device',
);

// Only error/pending paths are exercised — success paths attach Convex auth,
// and no ConvexClient is wired in these tests.
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

  // Sign-up cannot be submitted until both consent boxes are ticked, so every
  // sign-up path has to do this first (the labels are asserted here on
  // purpose: the copy is what the user is agreeing to).
  Future<void> acceptLegalChecks(WidgetTester tester) async {
    await tester.tap(find.text('Tengo 18 años o más'));
    await tester.pump();
    // The accept label carries the document links inline, and tapping one of
    // those opens the document instead of ticking the box. Aim at the start of
    // the sentence ("Acepto los "), which is always plain text.
    final label = find.text(
      'Acepto los Términos y Condiciones y la Política de Privacidad',
    );
    final topLeft = tester.getTopLeft(label);
    await tester.tapAt(Offset(topLeft.dx + 20, topLeft.dy + 8));
    await tester.pump();
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
    await acceptLegalChecks(tester);
    // The consent block pushes the submit button below the fold on a short
    // window; the panel is a scroll view, so bring it into view first.
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.pump();
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();

    expect(requests.single.url.path, '/auth/email/sign-up');
    expect(find.text('Verificá tu correo'), findsOneWidget);
    expect(find.text('Ya verifiqué'), findsOneWidget);
    // Cooldown just started: the resend button shows the countdown, disabled.
    expect(find.textContaining('Reenviar en'), findsOneWidget);
    expect(auth.accounts, isEmpty);

    await drainResendCooldown(tester);
    expect(find.text('Reenviar correo'), findsOneWidget);
  });

  testWidgets('sign-up is blocked until both consent boxes are ticked', (
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

    // Age alone is not acceptance: the button must stay dead, and nothing may
    // reach the network.
    await tester.tap(find.text('Tengo 18 años o más'));
    await tester.pump();
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.pump();
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    await tester.ensureVisible(
      find.text(
        'Acepto los Términos y Condiciones y la Política de Privacidad',
      ),
    );
    await tester.pump();
    await tester.tap(
      find.text(
        'Acepto los Términos y Condiciones y la Política de Privacidad',
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.pump();
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();

    expect(requests.single.url.path, '/auth/email/sign-up');
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    final acceptance = body['acceptance'] as Map<String, Object?>;
    expect(acceptance['documents'], ['terms', 'privacy']);
    expect(acceptance['ageConfirmed'], isTrue);
    // The server stamps the version; the client never names one.
    expect(acceptance.containsKey('version'), isFalse);
  });

  testWidgets('sign-up on a registered email says so instead of pending', (
    tester,
  ) async {
    final auth = AuthController(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'account_exists', 'message': 'exists'}),
          409,
        ),
      ),
    );
    await pumpLogin(tester, auth);

    await tester.tap(find.text('¿Necesitás una cuenta? Registrate'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@test.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await acceptLegalChecks(tester);
    // The consent block pushes the submit button below the fold on a short
    // window; the panel is a scroll view, so bring it into view first.
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.pump();
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();

    // The old behaviour parked the user here waiting for mail that never
    // gets sent; it must not appear.
    expect(find.text('Verificá tu correo'), findsNothing);
    // One message for both providers — naming the account's provider would
    // leak more than "this address is taken".
    expect(
      find.textContaining('con tu contraseña o con Google'),
      findsOneWidget,
    );
    // And the form drops back to sign-in so the hint is actionable.
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(auth.accounts, isEmpty);
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
    await tester.tap(find.text('Ya verifiqué'));
    await tester.pumpAndSettle();
    expect(find.text('ana@test.com'), findsOneWidget);

    // Signing in again while still unverified lands back on pending + notice.
    await tester.tap(find.text('Iniciar sesión').last);
    await tester.pumpAndSettle();
    expect(find.text('Verificá tu correo'), findsOneWidget);
    expect(
      find.text(
        'Ese correo todavía no está verificado. '
        'Te enviamos un enlace nuevo.',
      ),
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
    // A 200 from this endpoint now means the email really went out, so the
    // copy names the address instead of hedging with "if an account exists".
    expect(
      find.textContaining('Te enviamos un enlace a ana@test.com'),
      findsOneWidget,
    );

    // Back to sign in keeps the email around.
    await tester.tap(find.text('Volver a iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('ana@test.com'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });

  testWidgets('forgot password on an unknown address does not claim a send', (
    tester,
  ) async {
    final auth = AuthController(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'account_not_found', 'message': 'no account'}),
          404,
        ),
      ),
    );
    await pumpLogin(tester, auth);

    await tester.enterText(find.byType(TextFormField).at(0), 'ghost@test.com');
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    // The form used to flip to the sent state on any 200, and the endpoint
    // answered 200 for addresses it had never sent anything to.
    expect(find.textContaining('Te enviamos un enlace'), findsNothing);
    expect(
      find.text('No existe una cuenta para ghost@test.com.'),
      findsOneWidget,
    );
    // Still on the form, so the address can be corrected and retried.
    expect(find.text('Enviar enlace'), findsOneWidget);
  });

  testWidgets('resending to an already verified address says so', (
    tester,
  ) async {
    var call = 0;
    final auth = AuthController(
      httpClient: MockClient((request) async {
        call += 1;
        // First call is the blocked sign-in that opens the pending panel; the
        // second is the resend.
        return call == 1
            ? http.Response(
                jsonEncode({'code': 'email_not_verified', 'message': 'verify'}),
                403,
              )
            : http.Response(
                jsonEncode({
                  'code': 'email_already_verified',
                  'message': 'verified',
                }),
                409,
              );
      }),
    );
    await pumpLogin(tester, auth);

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@test.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Iniciar sesión').last);
    await tester.pumpAndSettle();
    expect(find.text('Verificá tu correo'), findsOneWidget);

    await drainResendCooldown(tester);
    await tester.tap(find.text('Reenviar correo'));
    await tester.pumpAndSettle();

    // There was nothing to re-send — every Google-registered address lands
    // here, and used to be told the link was on its way.
    expect(find.text('Te reenviamos el correo de verificación.'), findsNothing);
    expect(
      find.text('Ese correo ya está verificado. Iniciá sesión con tu cuenta.'),
      findsOneWidget,
    );
    // And no cooldown, so the reason stays reachable instead of a dead button.
    expect(find.text('Reenviar correo'), findsOneWidget);
  });

  testWidgets('promoting offers only the online path, with its own intro', (
    tester,
  ) async {
    final auth = AuthController(awaitFrame: () async {});
    final local = await auth.addLocal(name: 'Mine');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<AppConfigController>(
            create: (_) => AppConfigController(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(
            canDismiss: true,
            promotion: LocalPromotion(
              accountId: local.id,
              beforeConvert: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Create an online account and everything you have so far will be '
        'synced to it.',
      ),
      findsOneWidget,
    );
    // No local-account option: the account being promoted already is one.
    expect(find.text('Local account'), findsNothing);
    // Opens on sign-up and offers no way to sign in to an existing account.
    expect(find.text('Sign up'), findsWidgets);
    expect(find.text('Forgot your password?'), findsNothing);
    expect(find.text('Already have an account? Sign in'), findsNothing);
    expect(find.text('Need an account? Sign up'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
