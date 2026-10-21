import 'package:app/app_config/app_config_controller.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/activity.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('tab history', () {
    test('starts with nothing to go back to', () {
      final nav = AppNavigation();
      expect(nav.canGoBack, isFalse);
      expect(nav.goBack(), isFalse);
      expect(nav.index, AppNavigation.homeTab);
    });

    test('back walks the visited tabs in reverse', () {
      final nav = AppNavigation()
        ..index = AppNavigation.activityTab
        ..index = AppNavigation.accountsTab;

      expect(nav.goBack(), isTrue);
      expect(nav.index, AppNavigation.activityTab);
      expect(nav.goBack(), isTrue);
      expect(nav.index, AppNavigation.homeTab);
      expect(nav.canGoBack, isFalse);
    });

    test('returning to a tab drops its earlier entry', () {
      final nav = AppNavigation()
        ..index = AppNavigation.activityTab
        ..index = AppNavigation.accountsTab
        ..index = AppNavigation.activityTab;

      nav.goBack();
      expect(nav.index, AppNavigation.accountsTab);
      nav.goBack();
      expect(nav.index, AppNavigation.homeTab);
      expect(nav.canGoBack, isFalse);
    });

    test('selecting the current tab adds nothing', () {
      final nav = AppNavigation()
        ..index = AppNavigation.activityTab
        ..index = AppNavigation.activityTab;

      nav.goBack();
      expect(nav.index, AppNavigation.homeTab);
      expect(nav.canGoBack, isFalse);
    });

    test('opening Activity with a filter is a visit back can leave', () {
      final nav = AppNavigation()..index = AppNavigation.accountsTab;
      nav.openActivityForAccount('acc');
      expect(nav.takePendingActivityFilter()?.accountIds, {'acc'});
      nav.noteActivityFilterReplaced(const TransactionFilter(search: 'mine'));

      nav.goBack();
      expect(nav.index, AppNavigation.accountsTab);
      expect(nav.takePendingActivityFilter()?.search, 'mine');
    });

    test('back from a visit that kept the filter restores nothing', () {
      final nav = AppNavigation()
        ..index = AppNavigation.activityTab
        ..index = AppNavigation.accountsTab;

      nav.goBack();
      expect(nav.takePendingActivityFilter(), isNull);
    });

    test('a filter replaced while another tab is current is not recorded', () {
      final nav = AppNavigation()
        ..index = AppNavigation.activityTab
        ..index = AppNavigation.homeTab;
      nav.noteActivityFilterReplaced(const TransactionFilter(search: 'x'));

      nav.goBack();
      expect(nav.takePendingActivityFilter(), isNull);
    });

    test('a merged Activity visit keeps the first restore point', () {
      final nav = AppNavigation()..index = AppNavigation.accountsTab;
      nav.openActivityForAccount('acc');
      nav.takePendingActivityFilter();
      nav.noteActivityFilterReplaced(const TransactionFilter(search: 'first'));
      nav
        ..index = AppNavigation.insightsTab
        ..index = AppNavigation.activityTab;

      nav.goBack();
      expect(nav.index, AppNavigation.insightsTab);
      expect(nav.takePendingActivityFilter()?.search, 'first');
    });
  });

  group('Activity filter on back', () {
    late AppDatabase db;
    late AppNavigation nav;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      nav = AppNavigation();
    });

    tearDown(() => db.close());

    String searchText(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField, skipOffstage: false).first)
        .controller!
        .text;

    testWidgets('back from a "see all" visit puts the old filter back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppRepositories>.value(value: AppRepositories(db)),
            ChangeNotifierProvider<AppNavigation>.value(value: nav),
            ChangeNotifierProvider<AppConfigController>(
              create: (_) => AppConfigController(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const _TabShell(),
          ),
        ),
      );
      nav.index = AppNavigation.activityTab;
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'mine');
      await tester.pumpAndSettle();

      nav.index = AppNavigation.accountsTab;
      await tester.pumpAndSettle();
      nav.openActivityForAccount('acc');
      await tester.pumpAndSettle();
      expect(searchText(tester), isEmpty);

      nav.goBack();
      await tester.pumpAndSettle();
      expect(nav.index, AppNavigation.accountsTab);
      expect(searchText(tester), 'mine');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

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
