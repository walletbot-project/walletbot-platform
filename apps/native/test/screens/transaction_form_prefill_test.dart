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
  group('TransactionFormPrefill.fromFilter', () {
    test('an empty filter prefills nothing', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(),
      );
      expect(prefill.type, isNull);
      expect(prefill.accountId, isNull);
      expect(prefill.destinationAccountId, isNull);
      expect(prefill.categoryId, isNull);
    });

    test('a single type, account and category are prefilled', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(
          types: {TxnType.expense},
          accountIds: {'acc'},
          categoryIds: {'cat'},
        ),
      );
      expect(prefill.type, TransactionFormType.expense);
      expect(prefill.accountId, 'acc');
      expect(prefill.destinationAccountId, isNull);
      expect(prefill.categoryId, 'cat');
    });

    test('several values in a dimension prefill nothing for it', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(
          types: {TxnType.expense, TxnType.income},
          accountIds: {'a', 'b'},
          categoryIds: {'x', 'y'},
        ),
      );
      expect(prefill.type, isNull);
      expect(prefill.accountId, isNull);
      expect(prefill.categoryId, isNull);
    });

    test('a balance adjustment filter leaves the type alone', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(types: {TxnType.balanceAdjustment}),
      );
      expect(prefill.type, isNull);
    });

    test('a transfer never gets a category', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(
          types: {TxnType.transfer},
          categoryIds: {'cat'},
        ),
      );
      expect(prefill.type, TransactionFormType.transfer);
      expect(prefill.categoryId, isNull);
    });

    test('a destination account fills the transfer destination', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(
          types: {TxnType.transfer},
          accountIds: {'acc'},
          accountDirection: AccountDirection.destination,
        ),
      );
      expect(prefill.accountId, isNull);
      expect(prefill.destinationAccountId, 'acc');
    });

    test('a destination account without a transfer type fills nothing', () {
      final prefill = TransactionFormPrefill.fromFilter(
        const TransactionFilter(
          accountIds: {'acc'},
          accountDirection: AccountDirection.destination,
        ),
      );
      expect(prefill.accountId, isNull);
      expect(prefill.destinationAccountId, isNull);
    });

    test('an advanced filter prefills nothing', () {
      final prefill = TransactionFormPrefill.fromFilter(
        TransactionFilter.advanced(
          const FilterGroup(
            combinator: 'or',
            children: [
              FilterCondition(
                field: 'type',
                operator: 'in',
                value: ['expense'],
              ),
              FilterCondition(
                field: 'text',
                operator: 'contains',
                value: 'bus',
              ),
            ],
          ),
        ),
      );
      expect(prefill.type, isNull);
    });
  });

  group('TransactionFormScreen prefills', () {
    late AppDatabase db;
    late AppRepositories repos;
    late AppConfigController config;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = AppRepositories(db);
      config = AppConfigController();
    });

    tearDown(() async {
      config.dispose();
      await db.close();
    });

    Future<void> pumpForm(
      WidgetTester tester,
      TransactionFormScreen form,
    ) async {
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
            home: form,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('type, account and category start on the prefills', (
      tester,
    ) async {
      await repos.accounts.create(name: 'Account First', currency: 'ARS');
      final second = await repos.accounts.create(
        name: 'Account Second',
        currency: 'ARS',
      );
      await repos.categories.create(name: 'Category First');
      final category = await repos.categories.create(name: 'Category Second');

      await pumpForm(
        tester,
        TransactionFormScreen(
          initialType: TransactionFormType.expense,
          initialAccountId: second,
          initialCategoryId: category,
        ),
      );

      final selector = tester.widget<SegmentedButton<TransactionFormType>>(
        find.byType(SegmentedButton<TransactionFormType>),
      );
      expect(selector.selected, {TransactionFormType.expense});
      expect(find.text('Account Second'), findsOneWidget);
      expect(find.text('Account First'), findsNothing);
      expect(find.text('Category Second'), findsOneWidget);
      expect(find.text('Category First'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a prefilled destination keeps the source on another account', (
      tester,
    ) async {
      final first = await repos.accounts.create(
        name: 'Account First',
        currency: 'ARS',
      );
      await repos.accounts.create(name: 'Account Second', currency: 'ARS');

      await pumpForm(
        tester,
        TransactionFormScreen(
          initialType: TransactionFormType.transfer,
          initialDestinationAccountId: first,
        ),
      );

      final source = tester.getTopLeft(find.text('Account Second ARS'));
      final destination = tester.getTopLeft(find.text('Account First ARS'));
      expect(source.dx, lessThan(destination.dx));
      expect(tester.takeException(), isNull);
    });
  });
}
