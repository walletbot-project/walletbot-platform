import 'dart:convert';

import 'package:app/components/dashboard/balance_comparison_widget.dart';
import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The balance comparison tile: last month's closing balance (its last day
/// counted whole), the current balance, and the difference.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    // Streams must close synchronously under the widget tester's fake clock,
    // or cancelling one leaves a pending drift timer behind (same setup as
    // tags_view_reorder_test.dart).
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repos = AppRepositories(db);
  });

  tearDown(() => db.close());

  group('monthCloseAsOfMs', () {
    test('is the local midnight that starts the month', () {
      expect(
        monthCloseAsOfMs(DateTime(2026, 10, 3, 15, 30)),
        BigInt.from(DateTime(2026, 10).millisecondsSinceEpoch),
      );
      expect(
        monthCloseAsOfMs(DateTime(2026, 10)),
        BigInt.from(DateTime(2026, 10).millisecondsSinceEpoch),
      );
    });

    test('crosses the year on the first of January', () {
      expect(
        monthCloseAsOfMs(DateTime(2027, 1, 1, 0, 5)),
        BigInt.from(DateTime(2027).millisecondsSinceEpoch),
      );
    });
  });

  test('a stored balance_comparison row reads as its own spec', () async {
    await repos.dashboard.create(
      type: 'balance_comparison',
      filterId: null,
      position: 0,
      width: 'half',
      options: jsonEncode({
        'title': 'Este mes',
        'currency': 'ARS',
        'accountIds': ['a', 'a', ''],
      }),
    );
    final row = await db.select(db.dashboardWidgets).getSingle();
    final spec = dashboardSpecFromRow(row, const {});
    expect(spec, isA<BalanceComparisonWidgetSpec>());
    spec as BalanceComparisonWidgetSpec;
    expect(spec.title, 'Este mes');
    expect(spec.currency, 'ARS');
    expect(spec.accountIds, ['a']);
    expect(spec.width, DashboardWidth.half);
  });

  testWidgets('shows last month, now, and the difference', (tester) async {
    final cash = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    final category = await repos.categories.create(name: 'General');
    final monthStart = DateTime.now().copyWith(
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      millisecond: 0,
      microsecond: 0,
    );
    Future<void> income(int cents, DateTime at) => repos.transactions.addIncome(
      accountId: cash,
      categoryId: category,
      name: 'Income',
      amountCents: BigInt.from(cents),
      currency: 'ARS',
      dateMs: BigInt.from(at.millisecondsSinceEpoch),
      timeStatus: TransactionTimeStatus.confirmed,
    );
    // Earlier last month, and the last minute of its last day: both close it.
    await income(60000, monthStart.subtract(const Duration(days: 10)));
    await income(40000, monthStart.subtract(const Duration(minutes: 1)));
    // The very first instant of this month belongs to this month.
    await repos.transactions.addExpense(
      accountId: cash,
      categoryId: category,
      name: 'Expense',
      amountCents: BigInt.from(20000),
      currency: 'ARS',
      dateMs: BigInt.from(monthStart.millisecondsSinceEpoch),
      timeStatus: TransactionTimeStatus.confirmed,
    );

    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: BalanceComparisonWidget(
              spec: BalanceComparisonWidgetSpec(title: '', currency: 'ARS'),
            ),
          ),
        ),
      ),
    );
    // Drift's watch streams answer on real async, which the fake clock never
    // advances; and the loading spinner animates forever, so pumpAndSettle
    // would never return. Let the queries run for real, then paint.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    String amount(int cents) => formatCentsUnsigned(cents, locale: 'en');
    expect(find.text("Last month's balance"), findsOneWidget);
    expect(find.text('ARS ${amount(100000)}'), findsOneWidget);
    expect(find.text('Current balance'), findsOneWidget);
    expect(find.text('ARS ${amount(80000)}'), findsOneWidget);
    expect(find.text('Difference'), findsOneWidget);
    expect(find.text('-ARS ${amount(20000)}'), findsOneWidget);
  });
}
