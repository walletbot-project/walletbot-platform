import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/settings.dart';
import 'package:app/settings/display_settings.dart';
import 'package:app/shared/breakpoints.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_display_settings_store.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows the settings title in the app bar', (tester) async {
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings));

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.title, isA<Text>());
    expect((appBar.title! as Text).data, 'Settings');
    expect(find.byType(SliverAppBar), findsNothing);
  });

  testWidgets('orders language choices alphabetically in English', (
    tester,
  ) async {
    _useCompactWindow(tester);
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings));

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    _expectVerticalOrder(tester, ['English', 'Spanish', 'System default']);
  });

  testWidgets('orders language choices alphabetically in Spanish', (
    tester,
  ) async {
    _useCompactWindow(tester);
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await settings.setLanguage(DisplayLanguage.spanish);
    await tester.pumpWidget(_SettingsTestApp(settings: settings));

    await tester.tap(find.text('Idioma'));
    await tester.pumpAndSettle();

    _expectVerticalOrder(tester, [
      'Español',
      'Inglés',
      'Predeterminado del sistema',
    ]);
  });

  testWidgets('changes the app language immediately', (tester) async {
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings));

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();

    expect(settings.language, DisplayLanguage.spanish);
    expect(find.text('Configuración'), findsWidgets);
    expect(find.text('Español'), findsOneWidget);
  });

  testWidgets('changes the app theme immediately', (tester) async {
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings));

    expect(
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(settings.theme, DisplayTheme.dark);
    expect(
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('shows the delete account tile only for remote accounts', (
    tester,
  ) async {
    final settings = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings));
    expect(find.text('Delete my account'), findsNothing);

    final remote = _FakeAuthController(
      active: const UserAccount(
        id: 'u1',
        type: AccountType.remote,
        email: 'a@b.c',
      ),
    );
    await tester.pumpWidget(_SettingsTestApp(settings: settings, auth: remote));
    expect(find.text('Delete my account'), findsOneWidget);

    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('a@b.c'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsNothing);
  });
}

/// The choice pickers are bottom sheets only below [Breakpoints.medium] — at
/// or above it they present as dialogs (see `showAdaptiveModal`). The default
/// 800x600 test surface is already past that, so tests that assert
/// sheet-specific framing must pin the window to a phone size.
void _useCompactWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void _expectVerticalOrder(WidgetTester tester, List<String> labels) {
  // Scoped to the sheet so the settings tile behind it — which shows the
  // current value, e.g. "System default" — doesn't match too.
  final sheet = find.byType(BottomSheet);
  final positions = labels
      .map(
        (label) => tester.getTopLeft(
          find.descendant(of: sheet, matching: find.text(label)),
        ),
      )
      .map((offset) => offset.dy)
      .toList();

  expect(positions, orderedEquals([...positions]..sort()));
}

/// SettingsScreen only reads `activeAccount`, so the fake overrides just
/// that — a real AuthController would need ConvexClient, which can't
/// initialize under `flutter test`. Never disposed, same as the controllers
/// in auth_controller_email_flows_test.dart.
class _FakeAuthController extends AuthController {
  _FakeAuthController({UserAccount? active}) : _active = active;

  final UserAccount? _active;

  @override
  UserAccount? get activeAccount => _active;
}

final _noAccountAuth = _FakeAuthController();

class _SettingsTestApp extends StatelessWidget {
  const _SettingsTestApp({required this.settings, this.auth});

  final DisplaySettingsController settings;
  final AuthController? auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DisplaySettingsController>.value(
          value: settings,
        ),
        ChangeNotifierProvider<AuthController>.value(
          value: auth ?? _noAccountAuth,
        ),
        ChangeNotifierProvider(
          create: (_) =>
              DefaultCurrencyController(accountId: 'test', isRemote: false),
        ),
      ],
      child: Consumer<DisplaySettingsController>(
        builder: (context, value, _) => MaterialApp(
          locale: value.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.greenAccent,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.greenAccent,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: value.themeMode,
          home: const SettingsScreen(),
        ),
      ),
    );
  }
}
