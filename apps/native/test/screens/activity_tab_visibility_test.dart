import 'package:app/app_config/app_config_controller.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Activity's detail and form routes are pushed on the SHARED navigator, above
/// every tab. Leaving one open, switching tabs and then resizing must not
/// hand the window to a tab the user is not looking at.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late AppNavigation nav;
  late _PageRouteLog routes;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    nav = AppNavigation()..index = AppNavigation.activityTab;
    routes = _PageRouteLog();
  });

  tearDown(() => db.close());

  Widget harness() {
    return MultiProvider(
      providers: [
        Provider<AppRepositories>.value(value: repos),
        ChangeNotifierProvider<AppNavigation>.value(value: nav),
        ChangeNotifierProvider<AppConfigController>(
          create: (_) => AppConfigController(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [routes],
        home: const _TabShell(),
      ),
    );
  }

  void resize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
  }

  // Cancels Drift query streams and flushes their zero-duration cleanup
  // timer before the binding verifies pending timers.
  Future<void> drainStreams(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'the new-transaction form left open on a hidden Activity does not take '
    'over the window on shrink',
    (tester) async {
      resize(tester, const Size(1200, 800));
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Expanded: the form opens in the pane, no route involved.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionFormScreen), findsOneWidget);
      expect(routes.pushed, isEmpty);

      // Leave for another tab, then shrink the window. Activity is no longer
      // what the user is looking at, so its form must stay put.
      nav.index = AppNavigation.homeTab;
      await tester.pumpAndSettle();
      resize(tester, const Size(500, 800));
      await tester.pumpAndSettle();
      expect(find.text('otherTab'), findsOneWidget);
      expect(routes.pushed, isEmpty);

      // Coming back to Activity presents it again, now as the real route.
      nav.index = AppNavigation.activityTab;
      await tester.pumpAndSettle();
      expect(routes.pushed, hasLength(1));
      expect(find.byType(TransactionFormScreen), findsOneWidget);

      await drainStreams(tester);
    },
  );
}

/// The two tabs Activity actually lives between, in the same [IndexedStack]
/// the app shell uses — so a hidden Activity is built but not painted, exactly
/// as in production.
class _TabShell extends StatelessWidget {
  const _TabShell();

  @override
  Widget build(BuildContext context) {
    final index = context.watch<AppNavigation>().index;
    return IndexedStack(
      index: index == AppNavigation.activityTab ? 1 : 0,
      children: const [
        Scaffold(body: Center(child: Text('otherTab'))),
        ActivityScreen(),
      ],
    );
  }
}

/// Records the page routes pushed on the shared navigator, so a test can prove
/// none appeared over another tab.
class _PageRouteLog extends NavigatorObserver {
  final List<Route<void>> pushed = [];

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    // The MaterialApp's own home route is not a push over another tab.
    if (previousRoute != null) pushed.add(route);
  }

  @override
  void didRemove(Route<void> route, Route<void>? previousRoute) {
    pushed.remove(route);
  }

  @override
  void didPop(Route<void> route, Route<void>? previousRoute) {
    pushed.remove(route);
  }
}
