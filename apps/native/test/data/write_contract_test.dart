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
        .update(db.savedFilters)
        .write(const SavedFiltersCompanion(dirty: Value(false)));
    await db
        .update(db.dashboardWidgets)
        .write(const DashboardWidgetsCompanion(dirty: Value(false)));
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

  group('savedFilters', () {
    test('create/update/archive uphold the contract', () async {
      final id = await repos.savedFilters.create(
        name: 'Gastos',
        config: '{"combinator":"and","children":[]}',
      );
      var row = (await repos.savedFilters.getById(id))!;
      expect(row.dirty, isTrue);
      expect(row.updatedAt, row.createdAt);

      await clearAllDirty();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.savedFilters.update(id, name: const Value('Egresos'));
      row = (await repos.savedFilters.getById(id))!;
      expect(row.name, 'Egresos');
      expect(row.dirty, isTrue);
      expect(row.updatedAt.compareTo(row.createdAt) > 0, isTrue);

      await repos.savedFilters.archive(id);
      row = (await repos.savedFilters.getById(id))!;
      expect(row.archived, isTrue);
      expect(row.dirty, isTrue);
      expect(await tombstoneFor('savedFilters', id), isNotNull);
    });
  });

  group('dashboardWidgets', () {
    test('create/update/archive uphold the contract', () async {
      final id = await repos.dashboard.create(
        type: 'balance',
        position: 0,
        width: 'full',
        options: '{"title":"Saldo","currency":"ARS"}',
      );
      var row = (await repos.dashboard.getById(id))!;
      expect(row.dirty, isTrue);
      expect(row.updatedAt, row.createdAt);

      await clearAllDirty();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.dashboard.update(id, width: const Value('half'));
      row = (await repos.dashboard.getById(id))!;
      expect(row.width, 'half');
      expect(row.dirty, isTrue);
      expect(row.updatedAt.compareTo(row.createdAt) > 0, isTrue);

      await repos.dashboard.archive(id);
      row = (await repos.dashboard.getById(id))!;
      expect(row.archived, isTrue);
      expect(row.dirty, isTrue);
      expect(await tombstoneFor('dashboardWidgets', id), isNotNull);
    });

    test(
      'reorder rewrites positions, re-dirties, and bumps updatedAt',
      () async {
        final a = await repos.dashboard.create(
          type: 'balance',
          position: 0,
          width: 'full',
          options: '{}',
        );
        final b = await repos.dashboard.create(
          type: 'stat',
          position: 1,
          width: 'third',
          options: '{}',
        );
        await clearAllDirty();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await repos.dashboard.reorder([b, a]);

        final rowB = (await repos.dashboard.getById(b))!;
        final rowA = (await repos.dashboard.getById(a))!;
        expect(rowB.position, 0);
        expect(rowA.position, 1);
        expect(rowB.dirty, isTrue);
        expect(rowA.dirty, isTrue);
        expect(rowA.updatedAt.compareTo(rowA.createdAt) > 0, isTrue);
      },
    );

    test('seedDefaultIfEmpty runs once, then guards', () async {
      var runs = 0;
      Future<void> seed() async {
        runs++;
        await repos.dashboard.create(
          type: 'balance',
          position: 0,
          width: 'full',
          options: '{}',
        );
      }

      await repos.dashboard.seedDefaultIfEmpty(seed);
      expect(runs, 1);
      expect(await repos.dashboard.listActive(), hasLength(1));

      // Second call is a no-op even though widgets now exist.
      await repos.dashboard.seedDefaultIfEmpty(seed);
      expect(runs, 1);
    });

    test(
      'seedDefaultIfEmpty skips writing when widgets already exist',
      () async {
        await repos.dashboard.create(
          type: 'stat',
          position: 0,
          width: 'third',
          options: '{}',
        );

        var runs = 0;
        await repos.dashboard.seedDefaultIfEmpty(() async => runs++);
        expect(runs, 0);
        expect(await repos.dashboard.listActive(), hasLength(1));

        // Guard is now set, so a later empty table won't re-seed.
        await repos.dashboard.archive(
          (await repos.dashboard.listActive()).single.id,
        );
        await repos.dashboard.seedDefaultIfEmpty(() async => runs++);
        expect(runs, 0);
      },
    );

    test('remote seed respects pulled dashboard deletion history', () async {
      final now = BigInt.from(1000);
      await db
          .into(db.tombstones)
          .insert(
            TombstonesCompanion.insert(
              entityTable: 'dashboardWidgets',
              entityId: 'deleted-widget',
              deletedAt: now,
              createdAt: now,
              updatedAt: now,
              dirty: const Value(false),
            ),
          );
      var runs = 0;

      await repos.dashboard.seedDefaultIfEmpty(
        () async => runs++,
        respectDeleteHistory: true,
      );

      expect(runs, 0);
      expect(await repos.dashboard.listActive(), isEmpty);
      final state = await db.select(db.syncState).getSingle();
      expect(state.dashboardSeeded, isTrue);
    });

    test('layout repair compare-and-write rejects a stale snapshot', () async {
      final id = await repos.dashboard.create(
        type: 'stat',
        position: 0,
        width: 'third',
        options: '{"title":"Before","layout":{"row":0,"col":6}}',
      );
      final observed = (await repos.dashboard.getById(id))!;
      await repos.dashboard.update(
        id,
        options: const Value('{"title":"After","layout":{"row":0,"col":0}}'),
      );

      final repaired = await repos.dashboard.applyLayoutIfUnchanged(
        [
          (
            id: id,
            options: '{"title":"Before","layout":{"row":0,"col":0}}',
            position: 0,
            width: 'third',
          ),
        ],
        {
          id: (
            options: observed.options,
            width: observed.width,
            updatedAt: observed.updatedAt,
          ),
        },
      );

      expect(repaired, isFalse);
      expect((await repos.dashboard.getById(id))!.options, contains('After'));
    });

    test(
      'layout repair compare-and-write persists a current snapshot',
      () async {
        final id = await repos.dashboard.create(
          type: 'stat',
          position: 4,
          width: 'third',
          options: '{"title":"Stat","layout":{"row":0,"col":6}}',
        );
        final observed = (await repos.dashboard.getById(id))!;

        final repaired = await repos.dashboard.applyLayoutIfUnchanged(
          [
            (
              id: id,
              options: '{"title":"Stat","layout":{"row":0,"col":0}}',
              position: 0,
              width: 'third',
            ),
          ],
          {
            id: (
              options: observed.options,
              width: observed.width,
              updatedAt: observed.updatedAt,
            ),
          },
        );

        final row = (await repos.dashboard.getById(id))!;
        expect(repaired, isTrue);
        expect(row.position, 0);
        expect(row.options, contains('"col":0'));
        expect(row.dirty, isTrue);
      },
    );
  });
}
