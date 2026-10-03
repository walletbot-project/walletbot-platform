import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/transaction_details_sheet.dart';
import 'package:app/shared/money.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The detail of a balance adjustment shows the declaration next to what the
/// app had computed for the account just before it, and never offers to move
/// the declaration in time.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, String transactionId) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Keyed so opening a second movement mounts a fresh screen, the way
        // the app pushes a new route for each detail.
        home: TransactionDetailsScreen(
          key: ValueKey(transactionId),
          transactionId: transactionId,
          repos: repos,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows what was declared and what the app showed', (
    tester,
  ) async {
    final cash = await repos.accounts.create(name: 'Efectivo', currency: 'ARS');
    final category = await repos.categories.create(name: 'Varios');
    final now = DateTime.now().millisecondsSinceEpoch;
    await repos.transactions.addIncome(
      accountId: cash,
      categoryId: category,
      name: 'Sueldo',
      amountCents: BigInt.from(300000),
      currency: 'ARS',
      dateMs: BigInt.from(now - 2 * 3600000),
      timeStatus: TransactionTimeStatus.confirmed,
    );
    final adj = await repos.transactions.addBalanceAdjustment(
      accountId: cash,
      balanceAfterCents: BigInt.from(500000),
      currency: 'ARS',
      dateMs: BigInt.from(now - 3600000),
      timeStatus: TransactionTimeStatus.confirmed,
    );

    await open(tester, adj);

    expect(find.text('Saldo declarado'), findsOneWidget);
    expect(find.text(formatMoney(500000, 'ARS')), findsWidgets);
    expect(find.text('Saldo que marcaba la app'), findsOneWidget);
    expect(find.text(formatMoney(300000, 'ARS')), findsOneWidget);
  });

  testWidgets('offers no way to change an adjustment date or time', (
    tester,
  ) async {
    final cash = await repos.accounts.create(name: 'Efectivo', currency: 'ARS');
    final category = await repos.categories.create(name: 'Varios');
    final expense = await repos.transactions.addExpense(
      accountId: cash,
      categoryId: category,
      name: 'Café',
      amountCents: BigInt.from(1500),
      currency: 'ARS',
    );
    final adj = await repos.transactions.addBalanceAdjustment(
      accountId: cash,
      balanceAfterCents: BigInt.from(500000),
      currency: 'ARS',
    );

    // An expense in edit mode can change its date, time, account and
    // category.
    await open(tester, expense);
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar'), findsNWidgets(4));

    // An adjustment keeps only the category: its date, time and account are
    // where the declaration was made.
    await open(tester, adj);
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar'), findsOneWidget);
  });
}
