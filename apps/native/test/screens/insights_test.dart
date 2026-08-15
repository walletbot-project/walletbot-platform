import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/create_category.dart';
import 'package:app/screens/insights.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Insights divided view: on expanded windows the app bar (title, add
// action, Categories/Tags tabs) belongs to the LEFT COLUMN — per-column app
// bars, divider to the top — and the add action opens the create form in the
// pane, never on top. On small windows nothing changes: full-width app bar,
// creation as a real pushed route.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late AppNavigation nav;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    nav = AppNavigation()..index = AppNavigation.insightsTab;
  });

  tearDown(() => db.close());

  Widget harness() {
    return MultiProvider(
      providers: [
        Provider<AppRepositories>.value(value: repos),
        ChangeNotifierProvider<AppNavigation>.value(value: nav),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InsightsScreen(),
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
    'expanded: app bar lives in the left column and + opens the create '
    'form in the pane, not on top',
    (tester) async {
      resize(tester, const Size(1200, 800));
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Divided view with the header confined to the list column: the tab
      // bar spans half the window, not all of it.
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(tester.getSize(find.byType(TabBar)).width, closeTo(599.5, 1));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // The form occupies the pane: half width, list column still visible,
      // and no route was pushed over the divided view (no back button — the
      // pane shows the explicit close instead).
      final form = find.byType(CreateCategoryScreen);
      expect(form, findsOneWidget);
      expect(tester.getSize(form).width, closeTo(599.5, 1));
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await drainStreams(tester);
    },
  );

  testWidgets(
    'form open in the pane survives shrinking to a real route and back',
    (tester) async {
      resize(tester, const Size(1200, 800));
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Comida');
      await tester.pump();

      // Shrink: the pane form hands off to a genuine full-screen route —
      // automatic back button — with the typed state intact.
      resize(tester, const Size(500, 800));
      await tester.pumpAndSettle();
      expect(find.byType(CreateCategoryScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Comida'), findsOneWidget);

      // Grow: back into the pane, route removed, state still intact.
      resize(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.text('Comida'), findsOneWidget);

      await drainStreams(tester);
    },
  );

  testWidgets(
    'compact: full-width app bar unchanged, + pushes a real route, back '
    'clears it',
    (tester) async {
      resize(tester, const Size(500, 800));
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Nothing divided: the screen's own app bar heads the whole width.
      expect(find.byType(VerticalDivider), findsNothing);
      expect(tester.getSize(find.byType(TabBar)).width, 500);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.byType(CreateCategoryScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CreateCategoryScreen), findsNothing);

      // The dismissal cleared the form state: growing shows the empty pane.
      resize(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      expect(find.byType(CreateCategoryScreen), findsNothing);
      expect(find.byType(VerticalDivider), findsOneWidget);

      await drainStreams(tester);
    },
  );
}
