import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// The Breakdown chart buckets the *same* filtered rows a list/stat would see,
// then groups + labels them. These tests pin the grouping semantics that the
// pie/bar/line renderers depend on: which bucket a row lands in, how buckets
// are sorted, that labels resolve from the live entity, and that transfers are
// excluded from the category view (mirroring SummaryRepository.byCategory).
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late String cashId;
  late String bankId;
  late String foodId;
  late String transportId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    bankId = await repos.accounts.create(name: 'Bank', currency: 'ARS');
    foodId = await repos.categories.create(name: 'Food');
    transportId = await repos.categories.create(name: 'Transport');
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<BreakdownSlice>> breakdown(BreakdownGroupBy groupBy) =>
      repos.summaries.watchBreakdown(const TransactionFilter(), groupBy).first;

  test(
    'groups by category, sums magnitudes, sorts by descending total',
    () async {
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Lunch',
        amountCents: BigInt.from(10000),
        currency: 'ARS',
      );
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Dinner',
        amountCents: BigInt.from(5000),
        currency: 'ARS',
      );
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: transportId,
        name: 'Bus',
        amountCents: BigInt.from(3000),
        currency: 'ARS',
      );

      final slices = await breakdown(BreakdownGroupBy.category);

      expect(slices, hasLength(2));
      // Largest bucket leads.
      expect(slices.first.key, foodId);
      expect(slices.first.label, 'Food');
      expect(slices.first.totalCents, BigInt.from(15000));
      expect(slices[1].key, transportId);
      expect(slices[1].label, 'Transport');
      expect(slices[1].totalCents, BigInt.from(3000));
    },
  );

  test('category view excludes transfers', () async {
    await repos.transactions.addExpense(
      accountId: cashId,
      categoryId: foodId,
      name: 'Lunch',
      amountCents: BigInt.from(10000),
      currency: 'ARS',
    );
    await repos.transactions.addTransfer(
      fromAccountId: cashId,
      toAccountId: bankId,
      name: 'Move',
      amountCents: BigInt.from(50000),
      currency: 'ARS',
      toAmountCents: BigInt.from(50000),
      toCurrency: 'ARS',
    );

    final slices = await breakdown(BreakdownGroupBy.category);

    // Only the expense's category bucket — the transfer is dropped.
    expect(slices, hasLength(1));
    expect(slices.single.key, foodId);
    expect(slices.single.totalCents, BigInt.from(10000));
  });

  test('groups by account with resolved names', () async {
    await repos.transactions.addExpense(
      accountId: cashId,
      categoryId: foodId,
      name: 'Lunch',
      amountCents: BigInt.from(2000),
      currency: 'ARS',
    );
    await repos.transactions.addExpense(
      accountId: bankId,
      categoryId: foodId,
      name: 'Groceries',
      amountCents: BigInt.from(8000),
      currency: 'ARS',
    );

    final slices = await breakdown(BreakdownGroupBy.account);

    expect(slices, hasLength(2));
    expect(slices.first.key, bankId);
    expect(slices.first.label, 'Bank');
    expect(slices.first.totalCents, BigInt.from(8000));
    expect(slices[1].key, cashId);
    expect(slices[1].label, 'Cash');
  });

  test('groups by month, sorted chronologically with month labels', () async {
    await repos.transactions.addExpense(
      accountId: cashId,
      categoryId: foodId,
      name: 'March',
      amountCents: BigInt.from(3000),
      currency: 'ARS',
      dateMs: BigInt.from(DateTime(2026, 3, 10).millisecondsSinceEpoch),
    );
    await repos.transactions.addExpense(
      accountId: cashId,
      categoryId: foodId,
      name: 'January',
      amountCents: BigInt.from(1000),
      currency: 'ARS',
      dateMs: BigInt.from(DateTime(2026, 1, 15).millisecondsSinceEpoch),
    );

    final slices = await breakdown(BreakdownGroupBy.month);

    expect(slices, hasLength(2));
    // Chronological, not by magnitude.
    expect(slices.first.key, '2026-01');
    expect(slices.first.label, 'ene 2026');
    expect(slices[1].key, '2026-03');
    expect(slices[1].label, 'mar 2026');
  });
}
