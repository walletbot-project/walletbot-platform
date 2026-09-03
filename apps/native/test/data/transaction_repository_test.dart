import 'dart:async';
import 'dart:convert';

import 'package:app/data/data.dart';
import 'package:app/data/recurrence.dart';
import 'package:app/database.dart';
import 'package:app/telemetry/business_metrics.dart';
import 'package:app/telemetry/telemetry_client.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  test('creation metrics are sent directly with caller attribution', () async {
    await db.close();
    FlutterSecureStorage.setMockInitialValues({});

    final captured = Completer<http.Request>();
    final telemetry = TelemetryClient(
      convexSiteUrl: 'https://example.convex.site',
      httpClient: MockClient((request) async {
        if (!captured.isCompleted) captured.complete(request);
        return http.Response('{"ok":true,"accepted":1}', 200);
      }),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    cashId = await repos.accounts.create(name: 'Cash', currency: 'ARS');
    foodId = await repos.categories.create(name: 'Food');
    repos = AppRepositories(db, businessMetrics: BusinessMetrics(telemetry));

    await repos.transactions.addExpense(
      accountId: cashId,
      categoryId: foodId,
      name: 'Voice expense',
      amountCents: BigInt.from(100),
      currency: 'ARS',
      createdBy: 'agent',
    );

    final request = await captured.future.timeout(const Duration(seconds: 1));
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final metrics = body['metrics'] as List<Object?>;
    final metric = metrics.single as Map<String, Object?>;

    expect(metric['name'], 'business.movements.created_count');
    expect(metric['source'], 'native');
    expect(metric['attributes'], {
      'movement_type': 'expense',
      'created_by': 'agent',
      'ingest_path': 'direct_client',
    });

    telemetry.dispose();
  });

  test(
    'account creation metrics are sent directly with caller attribution',
    () async {
      await db.close();
      FlutterSecureStorage.setMockInitialValues({});

      final captured = Completer<http.Request>();
      final telemetry = TelemetryClient(
        convexSiteUrl: 'https://example.convex.site',
        httpClient: MockClient((request) async {
          if (!captured.isCompleted) captured.complete(request);
          return http.Response('{"ok":true,"accepted":1}', 200);
        }),
      );
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = AppRepositories(db, businessMetrics: BusinessMetrics(telemetry));

      await repos.accounts.create(
        name: 'Agent cash',
        currency: 'ARS',
        createdBy: 'agent',
      );

      final request = await captured.future.timeout(const Duration(seconds: 1));
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final metrics = body['metrics'] as List<Object?>;
      final metric = metrics.single as Map<String, Object?>;

      expect(metric['name'], 'business.financial_accounts.created_count');
      expect(metric['source'], 'native');
      expect(metric['attributes'], {
        'created_by': 'agent',
        'ingest_path': 'direct_client',
      });

      telemetry.dispose();
    },
  );

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

      final search = await repos.transactions.list(
        const TransactionFilter(search: 'pizza'),
      );
      expect(search.map((t) => t.name), ['Pizza night']);

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

    test('advanced tree supports nested OR and NOT groups', () async {
      final transportId = await repos.categories.create(name: 'Transport');
      final pizza = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Pizza night',
        amountCents: BigInt.from(2000),
        currency: 'ARS',
      );
      await repos.transactions.addIncome(
        accountId: cashId,
        categoryId: foodId,
        name: 'Salary',
        amountCents: BigInt.from(100000),
        currency: 'ARS',
      );
      final bus = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: transportId,
        name: 'Bus',
        amountCents: BigInt.from(500),
        currency: 'ARS',
      );

      final nestedOr = await repos.transactions.list(
        TransactionFilter.advanced(
          FilterGroup(
            children: [
              const FilterCondition(
                field: 'type',
                operator: 'in',
                value: ['expense'],
              ),
              FilterGroup(
                combinator: 'or',
                children: [
                  FilterCondition(
                    field: 'category',
                    operator: 'in',
                    value: [foodId],
                  ),
                  const FilterCondition(
                    field: 'text',
                    operator: 'contains',
                    value: 'bus',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(nestedOr.map((t) => t.id).toSet(), {pizza, bus});

      final notBus = await repos.transactions.list(
        TransactionFilter.advanced(
          const FilterGroup(
            children: [
              FilterCondition(
                field: 'type',
                operator: 'in',
                value: ['expense'],
              ),
              FilterGroup(
                not: true,
                children: [
                  FilterCondition(
                    field: 'text',
                    operator: 'contains',
                    value: 'bus',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(notBus.map((t) => t.id), [pizza]);
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

  group('recurring series', () {
    /// A monthly rule anchored on the 15th, with no end date. 48 occurrences
    /// up front (`recurrenceHorizon`), indices 0..47.
    Future<String> createMonthlySeries({DateTime? endDate}) =>
        repos.transactions.addExpense(
          accountId: cashId,
          categoryId: foodId,
          name: 'Rent',
          amountCents: BigInt.from(150000),
          currency: 'ARS',
          dateMs: BigInt.from(
            DateTime(2026, 1, 15, 9, 30).millisecondsSinceEpoch,
          ),
          // Confirmed, so the anchor keeps the 09:30 it was given (an
          // unconfirmed time is replaced by the clock — see
          // `_resolveTransactionDate`) and the series can be asserted exactly.
          timeStatus: TransactionTimeStatus.confirmed,
          recurrence: RecurrenceDraft(
            frequency: RecurrenceFrequency.monthly,
            endDate: endDate,
          ),
        );

    /// Straight off the table, on purpose: the repository's read paths sit
    /// behind the occurrence cutoff, and a series spans both sides of it.
    Future<List<Transaction>> seriesRows(String recurrenceId) =>
        (db.select(db.transactions)
              ..where((t) => t.recurrenceId.equals(recurrenceId))
              ..orderBy([(t) => OrderingTerm.asc(t.recurrenceIndex)]))
            .get();

    Future<String> ruleIdOf(String transactionId) async {
      final txn = await repos.transactions.getById(transactionId);
      return txn!.recurrenceId!;
    }

    test('creates the whole batch up front, indexed from the anchor', () async {
      final id = await createMonthlySeries();
      final rows = await seriesRows(await ruleIdOf(id));

      expect(rows, hasLength(48));
      expect(rows.first.id, id);
      expect(rows.map((t) => t.recurrenceIndex), List.generate(48, (i) => i));
      // Index 12 is one year on, still the 15th — projected from the anchor.
      final twelfth = DateTime.fromMillisecondsSinceEpoch(
        rows[12].date.toInt(),
      );
      expect(twelfth, DateTime(2027, 1, 15, 9, 30));
    });

    test(
      'addOccurrences continues from the last occurrence, not the opened one',
      () async {
        final id = await createMonthlySeries();
        final ruleId = await ruleIdOf(id);
        final before = await seriesRows(ruleId);
        final lastBefore = DateTime.fromMillisecondsSinceEpoch(
          before.last.date.toInt(),
        );

        // The occurrence the user had open is not even an argument — the
        // top-up is addressed to the rule, so where they were standing cannot
        // affect where the new movements land. That is the guarantee; this
        // asserts the result of it.
        final added = await repos.transactions.addOccurrences(ruleId);
        expect(added, 48);

        final after = await seriesRows(ruleId);
        expect(after, hasLength(96));
        expect(
          after.map((t) => t.recurrenceIndex),
          List.generate(96, (i) => i),
          reason: 'indices stay contiguous — no gap and no duplicate',
        );

        // The first new occurrence is one month after the last old one, not
        // one month after occurrence 3.
        final firstNew = DateTime.fromMillisecondsSinceEpoch(
          after[48].date.toInt(),
        );
        expect(firstNew.isAfter(lastBefore), isTrue);
        expect(
          firstNew,
          DateTime(lastBefore.year, lastBefore.month + 1, 15, 9, 30),
        );

        // Every date distinct: a top-up that overlapped would double-charge.
        expect(after.map((t) => t.date).toSet(), hasLength(96));
      },
    );

    test('addOccurrences copies the anchor, not the last occurrence', () async {
      final id = await createMonthlySeries();
      final ruleId = await ruleIdOf(id);
      final before = await seriesRows(ruleId);

      // Edit one occurrence — the last one, the worst case, since that is
      // where the top-up continues from. Its edit must not leak into the new
      // movements: the anchor is the rule's shape, and redefining the future
      // series is the explicit choice that "this one and the ones after it"
      // exists to make.
      await repos.transactions.update(
        before.last.id,
        name: const Value('Rent (renegotiated)'),
        amount: Value(BigInt.from(999999)),
        accountId: Value(bankId),
      );

      await repos.transactions.addOccurrences(ruleId);
      final fresh = (await seriesRows(ruleId)).last;

      expect(fresh.name, 'Rent');
      expect(fresh.amount, BigInt.from(150000));
      expect(fresh.accountId, cashId);
      expect(fresh.categoryId, foodId);
      expect(fresh.currency, 'ARS');
      expect(fresh.type, 'expense');
      expect(fresh.dirty, isTrue, reason: 'new rows have to sync up');
    });

    test('an end date past the batch still creates every occurrence', () async {
      // The batch is only there to give an *open-ended* rule a finite size.
      // "Monthly until the end of 2035" is 120 movements, not the first 48.
      final id = await createMonthlySeries(
        endDate: DateTime(2035, 12, 31, 23, 59),
      );
      final rows = await seriesRows(await ruleIdOf(id));

      expect(rows, hasLength(120));
      expect(
        DateTime.fromMillisecondsSinceEpoch(rows.last.date.toInt()),
        DateTime(2035, 12, 15, 9, 30),
      );
    });

    test('addOccurrences refuses a rule with an end date', () async {
      // Ends inside the horizon, so the series is shorter than 48 and, by the
      // user's own choice, complete.
      final id = await createMonthlySeries(endDate: DateTime(2026, 6, 30));
      final ruleId = await ruleIdOf(id);
      final before = await seriesRows(ruleId);
      expect(before, hasLength(6));

      expect(await repos.transactions.addOccurrences(ruleId), 0);
      expect(await seriesRows(ruleId), hasLength(6));
    });

    test('addOccurrences is a no-op for an unknown rule', () async {
      expect(await repos.transactions.addOccurrences('nope'), 0);
    });

    test('watchSeries derives the count and the reach from the rows', () async {
      final id = await createMonthlySeries();
      final ruleId = await ruleIdOf(id);
      final rows = await seriesRows(ruleId);

      final series = await repos.transactions.watchSeries(ruleId).first;
      expect(series, isNotNull);
      expect(series!.count, 48);
      expect(
        series.coveredThrough,
        DateTime.fromMillisecondsSinceEpoch(rows.last.date.toInt()),
      );
    });

    test('watchSeries follows a top-up', () async {
      final id = await createMonthlySeries();
      final ruleId = await ruleIdOf(id);
      final before = await repos.transactions.watchSeries(ruleId).first;

      await repos.transactions.addOccurrences(ruleId);
      final after = await repos.transactions.watchSeries(ruleId).first;

      expect(before!.count, 48);
      expect(after!.count, 96);
      expect(after.coveredThrough!.isAfter(before.coveredThrough!), isTrue);
    });

    test('seriesOf reads the same series as watchSeries, once', () async {
      final id = await createMonthlySeries();
      final ruleId = await ruleIdOf(id);

      final watched = await repos.transactions.watchSeries(ruleId).first;
      final fetched = await repos.transactions.seriesOf(ruleId);

      expect(fetched, isNotNull);
      expect(fetched!.count, watched!.count);
      expect(fetched.coveredThrough, watched.coveredThrough);
      expect(fetched.rule.id, ruleId);
    });

    test('seriesOf is null for a one-off movement', () async {
      expect(await repos.transactions.seriesOf(null), isNull);
    });

    test('watchSeries is single-subscription — consume it once', () async {
      final id = await createMonthlySeries();
      final stream = repos.transactions.watchSeries(await ruleIdOf(id));
      await stream.first;

      // This is why the detail screen wraps its whole body in ONE
      // StreamBuilder: a second listener threw "Stream has already been
      // listened to" and painted the screen red as soon as a movement was
      // opened.
      expect(() => stream.listen((_) {}), throwsStateError);
    });

    test('watchSeries is null for a one-off movement', () async {
      final id = await repos.transactions.addExpense(
        accountId: cashId,
        categoryId: foodId,
        name: 'Coffee',
        amountCents: BigInt.from(500),
        currency: 'ARS',
      );
      final txn = await repos.transactions.getById(id);
      expect(txn!.recurrenceId, isNull);
      expect(await repos.transactions.watchSeries(null).first, isNull);
    });
  });
}
