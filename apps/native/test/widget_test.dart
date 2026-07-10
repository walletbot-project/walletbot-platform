import 'package:app/auth/auth_controller.dart';
import 'package:app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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

    await tester.pumpWidget(MyApp(auth: auth, locale: const Locale('es')));
    await tester.pump();

    expect(find.text('Sin cuenta'), findsWidgets);
  });

  testWidgets('requires a name before continuing without an account', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthController();

    await tester.pumpWidget(MyApp(auth: auth, locale: const Locale('es')));
    await tester.pump();

    await tester.tap(find.text('Sin cuenta').first);
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
    await tester.pumpWidget(MyApp(auth: auth, locale: const Locale('en')));
    await tester.pump();

    expect(find.text('Local account'), findsWidgets);
    await tester.tap(find.text('Local account').first);
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Continue locally'), findsOneWidget);
  });
}
