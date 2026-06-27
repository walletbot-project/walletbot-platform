import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// The sacred write contract (plan invariants #1/#2/#11):
//  - every repository write sets dirty=true and bumps updatedAt;
//  - every archive pairs with a tombstone in the same transaction;
//  - repositories never write dirty=false.
void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> clearAllDirty() async {
    // Simulates the sync engine's ack so the next write's dirty flag is
    // attributable to that write alone.
    await db
        .update(db.accounts)
        .write(const AccountsCompanion(dirty: Value(false)));
    await db
        .update(db.categories)
        .write(const CategoriesCompanion(dirty: Value(false)));
    await db.update(db.tags).write(const TagsCompanion(dirty: Value(false)));
    await db
        .update(db.transactions)
        .write(const TransactionsCompanion(dirty: Value(false)));
    await db
        .update(db.transactionTags)
        .write(const TransactionTagsCompanion(dirty: Value(false)));
    await db
        .update(db.tombstones)
        .write(const TombstonesCompanion(dirty: Value(false)));
  }

  Future<Tombstone?> tombstoneFor(String table, String id) =>
      (db.select(db.tombstones)
            ..where((t) => t.entityTable.equals(table) & t.entityId.equals(id)))
          .getSingleOrNull();

  group('accounts', () {
    test('create sets dirty and timestamps', () async {
      final id = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      final row = await repos.accounts.getById(id);
      expect(row, isNotNull);
      expect(row!.dirty, isTrue);
      expect(row.updatedAt, row.createdAt);
    });

    test('create with initial balance writes adjustment atomically', () async {
      final id = await repos.accounts.create(
        name: 'Bank',
        currency: 'ARS',
        initialBalanceCents: BigInt.from(123450),
      );
      final txns = await (db.select(db.transactions)).get();
      expect(txns, hasLength(1));
      final adj = txns.single;
      expect(adj.type, 'balance_adjustment');
      expect(adj.accountId, id);
      expect(adj.name, 'Balance inicial');
      expect(adj.amount, BigInt.from(123450));
      expect(adj.balanceAfter, BigInt.from(123450));
      expect(adj.categoryId, '');
      expect(adj.status, 'cleared');
      expect(adj.dirty, isTrue);

      expect(await repos.accounts.getBalanceCents(id), BigInt.from(123450));
    });

    test('update bumps updatedAt and re-dirties', () async {
      final id = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      await clearAllDirty();
      final before = (await repos.accounts.getById(id))!;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.accounts.update(id, name: const Value('Wallet'));

      final after = (await repos.accounts.getById(id))!;
      expect(after.name, 'Wallet');
      expect(after.dirty, isTrue);
      expect(after.updatedAt.compareTo(before.updatedAt) > 0, isTrue);
    });

    test('update with absent values leaves fields untouched', () async {
      final id = await repos.accounts.create(
        name: 'Cash',
        currency: 'ARS',
        description: 'efectivo',
      );
      await repos.accounts.update(id, color: const Value('#ff0000'));
      final row = (await repos.accounts.getById(id))!;
      expect(row.name, 'Cash');
      expect(row.description, 'efectivo');
      expect(row.color, '#ff0000');
    });

    test('archive pairs with tombstone', () async {
      final id = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      await repos.accounts.archive(id);

      final row = (await repos.accounts.getById(id))!;
      expect(row.archived, isTrue);
      expect(row.dirty, isTrue);

      final tomb = await tombstoneFor('accounts', id);
      expect(tomb, isNotNull);
      expect(tomb!.dirty, isTrue);
    });
  });

  group('categories', () {
    test('create/update/archive uphold the contract', () async {
      final id = await repos.categories.create(name: 'Food');
      var row = (await repos.categories.getById(id))!;
      expect(row.dirty, isTrue);

      await clearAllDirty();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.categories.update(id, name: const Value('Comida'));
      row = (await repos.categories.getById(id))!;
      expect(row.name, 'Comida');
      expect(row.dirty, isTrue);
      expect(row.updatedAt.compareTo(row.createdAt) > 0, isTrue);

      await repos.categories.archive(id);
      row = (await repos.categories.getById(id))!;
      expect(row.archived, isTrue);
      expect(await tombstoneFor('categories', id), isNotNull);
    });
  });

  group('tags', () {
    test('create/update/archive uphold the contract', () async {
      final id = await repos.tags.create(name: 'Work', color: '#00ff00');
      var row = (await repos.tags.getById(id))!;
      expect(row.dirty, isTrue);

      await clearAllDirty();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.tags.update(id, name: const Value('Trabajo'));
      row = (await repos.tags.getById(id))!;
      expect(row.name, 'Trabajo');
      expect(row.dirty, isTrue);

      await repos.tags.archive(id, mode: TagArchiveMode.reparentChildren);
      row = (await repos.tags.getById(id))!;
      expect(row.archived, isTrue);
      expect(await tombstoneFor('tags', id), isNotNull);
    });
  });

  group('transactions', () {
    late String accountId;
    late String categoryId;

    setUp(() async {
      accountId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
      categoryId = await repos.categories.create(name: 'Food');
    });

    test('addExpense sets dirty, defaults, and attaches tags', () async {
      final tagId = await repos.tags.create(name: 'Lunch');
      final id = await repos.transactions.addExpense(
        accountId: accountId,
        categoryId: categoryId,
        name: 'Sandwich',
        amountCents: BigInt.from(1500),
        currency: 'ARS',
        tagIds: [tagId],
      );
      final row = (await repos.transactions.getById(id))!;
      expect(row.type, 'expense');
      expect(row.status, 'cleared');
      expect(row.dirty, isTrue);
      expect(row.dateConfirmed, isTrue);

      final joins = await repos.transactions.tagIdsOf(id);
      expect(joins, [tagId]);
      final join = await (db.select(db.transactionTags)).getSingle();
      expect(join.id, '${id}__$tagId');
      expect(join.dirty, isTrue);
    });

    test('addTransfer rejects same-account transfers', () async {
      expect(
        () => repos.transactions.addTransfer(
          fromAccountId: accountId,
          toAccountId: accountId,
          name: 'Loop',
          amountCents: BigInt.from(100),
          currency: 'ARS',
          toAmountCents: BigInt.from(100),
          toCurrency: 'ARS',
        ),
        throwsArgumentError,
      );
    });

    test('addBalanceAdjustment stores delta against current balance', () async {
      await repos.transactions.addIncome(
        accountId: accountId,
        categoryId: categoryId,
        name: 'Salary',
        amountCents: BigInt.from(10000),
        currency: 'ARS',
      );
      final id = await repos.transactions.addBalanceAdjustment(
        accountId: accountId,
        balanceAfterCents: BigInt.from(25000),
        currency: 'ARS',
      );
      final row = (await repos.transactions.getById(id))!;
      expect(row.amount, BigInt.from(15000));
      expect(row.balanceAfter, BigInt.from(25000));
      expect(row.categoryId, '');
      expect(
        await repos.accounts.getBalanceCents(accountId),
        BigInt.from(25000),
      );
    });

    test('update bumps updatedAt and re-dirties', () async {
      final id = await repos.transactions.addExpense(
        accountId: accountId,
        categoryId: categoryId,
        name: 'Sandwich',
        amountCents: BigInt.from(1500),
        currency: 'ARS',
      );
      await clearAllDirty();
      final before = (await repos.transactions.getById(id))!;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.transactions.update(id, amount: Value(BigInt.from(2000)));

      final after = (await repos.transactions.getById(id))!;
      expect(after.amount, BigInt.from(2000));
      expect(after.dirty, isTrue);
      expect(after.updatedAt.compareTo(before.updatedAt) > 0, isTrue);
    });
  });
}
