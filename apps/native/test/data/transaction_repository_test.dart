import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late String cashId;
  late String bankId;
  late String foodId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    bankId = await repos.accounts.create(name: 'Bank', currency: 'ARS');
    foodId = await repos.categories.create(name: 'Food');
  });

  tearDown(() async {
    await db.close();
  });

  group('delete cascade (plan invariant #3)', () {
    test('N tags → N join tombstones + 1 transaction tombstone', () async {
      final tagA = await repos.tags.create(name: 'A');
      final tagB = await repos.tags.create(name: 'B');
      final id = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Tagged',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        tagIds: [tagA, tagB],
      );

      await repos.transactions.delete(id);

      final txn = (await repos.transactions.getById(id))!;
      expect(txn.archived, isTrue, reason: 'soft delete, never a row delete');
      expect(txn.dirty, isTrue);

      final joins = await (db.select(db.transactionTags)).get();
      expect(joins, isEmpty, reason: 'joins are hard-deleted');

      final tombs = await (db.select(db.tombstones)).get();
      final joinTombs = tombs
          .where((t) => t.entityTable == 'transactionTags')
          .toList();
      final txnTombs = tombs
          .where((t) => t.entityTable == 'transactions')
          .toList();
      expect(joinTombs, hasLength(2));
      expect(txnTombs, hasLength(1));
      expect(joinTombs.map((t) => t.entityId).toSet(), {
        '${id}__$tagA',
        '${id}__$tagB',
      });
    });

    test('deleting a missing transaction is a no-op', () async {
      await repos.transactions.delete('does-not-exist');
      expect(await (db.select(db.tombstones)).get(), isEmpty);
    });
  });

  group('addTags / removeTags', () {
    test(
      'idempotent attach with deterministic ids; tombstoned detach',
      () async {
        final tag = await repos.tags.create(name: 'A');
        final id = await repos.transactions.addExpense(
          accountId: cashId,
          categoryId: foodId,
          name: 'T',
          amountCents: BigInt.from(100),
          currency: 'ARS',
        );

        expect(await repos.transactions.addTags(id, [tag]), 1);
        expect(
          await repos.transactions.addTags(id, [tag]),
          0,
          reason: 'second attach is a no-op',
        );

        expect(await repos.transactions.removeTags(id, [tag]), 1);
        expect(await repos.transactions.removeTags(id, [tag]), 0);

        final tomb = await (db.select(
          db.tombstones,
        )..where((t) => t.entityTable.equals('transactionTags'))).getSingle();
        expect(tomb.entityId, '${id}__$tag');

        // Re-tag recreates the same join id (untag→retag round-trip semantics).
        await repos.transactions.addTags(id, [tag]);
        final join = await (db.select(db.transactionTags)).getSingle();
        expect(join.id, '${id}__$tag');
      },
    );
  });

  group('filtered reads (shared query builder)', () {
    test('type, account direction, and search filters', () async {
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Pizza night',
        amountCents: BigInt.from(2000),
        currency: 'ARS',
      );
      await repos.transactions.addIncome(
        accountId: cashId,
        categoryId: foodId,
        name: 'Refund',
        amountCents: BigInt.from(500),
        currency: 'ARS',
      );
      await repos.transactions.addTransfer(
        fromAccountId: cashId,
        toAccountId: bankId,
        name: 'To bank',
        amountCents: BigInt.from(1000),
        currency: 'ARS',
        toAmountCents: BigInt.from(1000),
        toCurrency: 'ARS',
      );

      final expenses = await repos.transactions.list(
        const TransactionFilter(types: {TxnType.expense}),
      );
      expect(expenses.map((t) => t.name), ['Pizza night']);

      // Direction: bank is only the *destination* of the transfer.
      final bankSource = await repos.transactions.list(
        TransactionFilter(
          accountIds: {bankId},
          accountDirection: AccountDirection.source,
        ),
      );
      expect(bankSource, isEmpty);

      final bankDest = await repos.transactions.list(
        TransactionFilter(
          accountIds: {bankId},
          accountDirection: AccountDirection.destination,
        ),
      );
      expect(bankDest.map((t) => t.name), ['To bank']);

      final bankEither = await repos.transactions.list(
        TransactionFilter(accountIds: {bankId}),
      );
      expect(bankEither.map((t) => t.name), ['To bank']);

      final titleSearch = await repos.transactions.list(
        const TransactionFilter(search: 'pizza night'),
      );
      expect(titleSearch.map((t) => t.name), ['Pizza night']);

      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Groceries',
        description: 'Pizza ingredients',
        amountCents: BigInt.from(800),
        currency: 'ARS',
      );

      final descriptionSearch = await repos.transactions.list(
        const TransactionFilter(search: 'ingredients'),
      );
      expect(descriptionSearch.map((t) => t.name), ['Groceries']);
    });

    test('tag match any/all and includeSubtags', () async {
      final parent = await repos.tags.create(name: 'Parent');
      final child = await repos.tags.create(name: 'Child', parentId: parent);
      final other = await repos.tags.create(name: 'Other');

      final withChild = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'child-tagged',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        tagIds: [child],
      );
      final withBoth = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'both-tagged',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        tagIds: [child, other],
      );
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'untagged',
        amountCents: BigInt.from(100),
        currency: 'ARS',
      );

      // Parent tag without subtags matches nothing (no direct joins).
      final parentOnly = await repos.transactions.list(
        TransactionFilter(tagIds: {parent}),
      );
      expect(parentOnly, isEmpty);

      // With subtags, the child's transactions match.
      final parentSubtags = await repos.transactions.list(
        TransactionFilter(tagIds: {parent}, includeSubtags: true),
      );
      expect(parentSubtags.map((t) => t.id).toSet(), {withChild, withBoth});

      // ALL: must carry a tag from each group.
      final all = await repos.transactions.list(
        TransactionFilter(
          tagIds: {parent, other},
          tagMatch: TagMatch.all,
          includeSubtags: true,
        ),
      );
      expect(all.map((t) => t.id), [withBoth]);

      // ANY: union of groups.
      final any = await repos.transactions.list(
        TransactionFilter(tagIds: {parent, other}, includeSubtags: true),
      );
      expect(any.map((t) => t.id).toSet(), {withChild, withBoth});
    });

    test('date range is end-day inclusive', () async {
      final base = DateTime(2026, 6, 10);
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'inside-late',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        dateMs: BigInt.from(
          DateTime(2026, 6, 10, 23, 30).millisecondsSinceEpoch,
        ),
      );
      await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'outside',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        dateMs: BigInt.from(
          DateTime(2026, 6, 11, 0, 30).millisecondsSinceEpoch,
        ),
      );

      final rows = await repos.transactions.list(
        TransactionFilter(
          dateRange: DateTimeRange(start: base, end: base),
        ),
      );
      expect(rows.map((t) => t.name), ['inside-late']);
    });

    test('watch with includeSubtags reacts to tag tree changes', () async {
      final parent = await repos.tags.create(name: 'Parent');
      final child = await repos.tags.create(name: 'Child'); // top-level so far
      final txn = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'child-tagged',
        amountCents: BigInt.from(100),
        currency: 'ARS',
        tagIds: [child],
      );

      final stream = repos.transactions.watch(
        TransactionFilter(tagIds: {parent}, includeSubtags: true),
      );
      final emissions = <List<String>>[];
      final sub = stream.listen(
        (rows) => emissions.add(rows.map((t) => t.id).toList()),
      );
      addTearDown(sub.cancel);

      // Initially the parent group is just {parent} → no matches.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.last, isEmpty);

      // Moving child under parent must re-expand the group and surface txn.
      await repos.tags.update(child, parentId: Value(parent));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions.last, [txn]);
    });
  });
}
