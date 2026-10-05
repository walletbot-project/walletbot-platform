import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A balance adjustment declares "this account holds X at this moment". Its
/// amount is derived from everything before it, so local writes — offline,
/// before any sync — must keep every declaration true on their own.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late String cashId;
  late String bankId;
  late String catId;

  const hour = 3600000;
  const day = 24 * hour;
  final base = DateTime.now().millisecondsSinceEpoch;
  BigInt at(int offsetMs) => BigInt.from(base + offsetMs);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    bankId = await repos.accounts.create(name: 'Bank', currency: 'ARS');
    catId = await repos.categories.create(name: 'General');
  });

  tearDown(() => db.close());

  Future<BigInt> amountOf(String id) async =>
      (await repos.transactions.getById(id))!.amount;

  Future<String> declare(String accountId, int cents, int offsetMs) =>
      repos.transactions.addBalanceAdjustment(
        accountId: accountId,
        balanceAfterCents: BigInt.from(cents),
        currency: 'ARS',
        dateMs: at(offsetMs),
        timeStatus: TransactionTimeStatus.confirmed,
      );

  Future<String> income(int cents, int offsetMs, {String? accountId}) =>
      repos.transactions.addIncome(
        accountId: accountId ?? cashId,
        categoryId: catId,
        name: 'Income',
        amountCents: BigInt.from(cents),
        currency: 'ARS',
        dateMs: at(offsetMs),
        timeStatus: TransactionTimeStatus.confirmed,
      );

  Future<String> expense(int cents, int offsetMs) =>
      repos.transactions.addExpense(
        accountId: cashId,
        categoryId: catId,
        name: 'Expense',
        amountCents: BigInt.from(cents),
        currency: 'ARS',
        dateMs: at(offsetMs),
        timeStatus: TransactionTimeStatus.confirmed,
      );

  test(
    'a back-dated income shrinks the declaration, deleting it restores it',
    () async {
      final init = await declare(cashId, 200000, -3 * day);
      final adj = await declare(cashId, 500000, -hour);
      expect(await amountOf(adj), BigInt.from(300000));

      // "Yesterday a debt of 1000 was paid back to me."
      final debt = await income(100000, -day);
      expect(await amountOf(adj), BigInt.from(200000));
      expect(await amountOf(init), BigInt.from(200000));
      expect(await repos.accounts.getBalanceCents(cashId), BigInt.from(500000));

      await repos.transactions.delete(debt);
      expect(await amountOf(adj), BigInt.from(300000));
      expect(await repos.accounts.getBalanceCents(cashId), BigInt.from(500000));
    },
  );

  test('a movement after the declaration does not change it', () async {
    final adj = await declare(cashId, 500000, -2 * hour);
    await expense(10000, -hour);
    expect(await amountOf(adj), BigInt.from(500000));
    expect(await repos.accounts.getBalanceCents(cashId), BigInt.from(490000));
  });

  test('a back-dated declaration is measured against its own date', () async {
    await income(100000, -5 * day);
    await expense(30000, -day);
    final adj = await declare(cashId, 150000, -3 * day);
    expect(await amountOf(adj), BigInt.from(50000));
  });

  test('editing a movement across declarations moves the absorption', () async {
    final first = await declare(cashId, 100000, -10 * day);
    final second = await declare(cashId, 300000, -2 * day);
    final spent = await expense(20000, -5 * day);
    expect(await amountOf(first), BigInt.from(100000));
    expect(await amountOf(second), BigInt.from(220000));

    await repos.transactions.update(
      spent,
      date: Value(at(-20 * day)),
      timeStatus: const Value(TransactionTimeStatus.confirmed),
    );
    expect(await amountOf(first), BigInt.from(120000));
    expect(await amountOf(second), BigInt.from(200000));

    // Moving it to another account takes it out of this ledger altogether.
    await repos.transactions.update(
      spent,
      accountId: Value(bankId),
      currency: const Value('ARS'),
    );
    expect(await amountOf(first), BigInt.from(100000));
  });

  test('a back-dated transfer moves both accounts\' declarations', () async {
    final cashAdj = await declare(cashId, 50000, -hour);
    final bankAdj = await declare(bankId, 900000, -hour);
    await repos.transactions.addTransfer(
      fromAccountId: bankId,
      toAccountId: cashId,
      name: 'ATM',
      amountCents: BigInt.from(20000),
      currency: 'ARS',
      toAmountCents: BigInt.from(20000),
      toCurrency: 'ARS',
      dateMs: at(-day),
      timeStatus: TransactionTimeStatus.confirmed,
    );
    expect(await amountOf(cashAdj), BigInt.from(30000));
    expect(await amountOf(bankAdj), BigInt.from(920000));
  });

  test('corrections are dirtied so the next push carries them', () async {
    final adj = await declare(cashId, 500000, -hour);
    await (db.update(db.transactions)..where((t) => t.id.equals(adj))).write(
      const TransactionsCompanion(dirty: Value(false)),
    );
    await income(100000, -day);
    final row = await repos.transactions.getById(adj);
    expect(row!.amount, BigInt.from(400000));
    expect(row.dirty, isTrue);
  });

  test('an adjustment amount, date and account cannot be edited', () async {
    final adj = await declare(cashId, 500000, -hour);
    expect(
      () => repos.transactions.update(adj, amount: Value(BigInt.one)),
      throwsArgumentError,
    );
    expect(
      () => repos.transactions.update(adj, date: Value(at(-day))),
      throwsArgumentError,
    );
    expect(
      () => repos.transactions.update(adj, accountId: Value(bankId)),
      throwsArgumentError,
    );
    // Name, and re-sending the same account as the detail sheet does, are fine.
    await repos.transactions.update(
      adj,
      name: const Value('Counted the drawer'),
      accountId: Value(cashId),
    );
    expect((await repos.transactions.getById(adj))!.name, 'Counted the drawer');
  });

  test(
    'around a declaration: what the platform had, then what was declared',
    () async {
      await income(300000, -day);
      final adj = await declare(cashId, 500000, -hour);
      final around = await repos.transactions.balanceAroundTransaction(
        transactionId: adj,
        accountId: cashId,
      );
      expect(around!.before, BigInt.from(300000));
      expect(around.after, BigInt.from(500000));
    },
  );
}
