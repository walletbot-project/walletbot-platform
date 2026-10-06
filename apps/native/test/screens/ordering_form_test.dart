import 'package:app/app_config/app_config_controller.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'native form respects account/category order and keeps tags alphabetical',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repos = AppRepositories(db);
      final config = AppConfigController();
      addTearDown(() async {
        config.dispose();
        await db.close();
      });
      final a = await repos.accounts.create(
        name: 'Account Alpha',
        currency: 'ARS',
      );
      final z = await repos.accounts.create(
        name: 'Account Zulu',
        currency: 'ARS',
      );
      await repos.accounts.reorder([z, a]);
      final ca = await repos.categories.create(name: 'Category Alpha');
      final cz = await repos.categories.create(name: 'Category Zulu');
      await repos.categories.reorder([cz, ca]);
      final ta = await repos.tags.create(name: 'Tag Alpha');
      final tz = await repos.tags.create(name: 'Tag Zulu');
      await repos.tags.reorder(null, [tz, ta]);
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppRepositories>.value(value: repos),
            ChangeNotifierProvider<AppConfigController>.value(value: config),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TransactionFormScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account Zulu'), findsOneWidget);
      expect(find.text('Category Zulu'), findsOneWidget);
      expect(find.text('Account Alpha'), findsNothing);
      await tester.tap(find.text('Account Zulu'));
      await tester.pumpAndSettle();
      final az = find.widgetWithText(ListTile, 'Account Zulu');
      final aa = find.widgetWithText(ListTile, 'Account Alpha');
      expect(tester.getTopLeft(az).dy, lessThan(tester.getTopLeft(aa).dy));
      await tester.tap(az);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category Zulu'));
      await tester.pumpAndSettle();
      final czw = find.widgetWithText(ListTile, 'Category Zulu');
      final caw = find.widgetWithText(ListTile, 'Category Alpha');
      expect(tester.getTopLeft(czw).dy, lessThan(tester.getTopLeft(caw).dy));
      await tester.tap(czw);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Tag Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Tag Zulu')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
