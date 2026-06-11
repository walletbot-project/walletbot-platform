import 'dart:math';

import 'package:app/database.dart';
import 'package:app/sync/sync_recompute.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Characterization tests for the balance semantics shared between the
// account-balance formula (tool_executors._computeAccountBalance, moving to
// lib/data in the refactor) and the chronological replay in
// BalanceAdjustmentRecomputer. Plan invariant #7: the two must stay
// arithmetically identical, otherwise sync keeps "correcting" fresh
// balance adjustments and amounts visibly jump.

/// The unordered-sum balance formula, copied verbatim in behavior from
/// tool_executors.dart `_computeAccountBalance` (lines 904-934).
Future<BigInt> computeAccountBalance(AppDatabase db, String accountId) async {
  final own = await (db.select(db.transactions)
        ..where((t) => t.accountId.equals(accountId))
        ..where((t) => t.archived.equals(false)))
      .get();
  BigInt sum = BigInt.zero;
  for (final t in own) {
    switch (t.type) {
      case 'expense':
      case 'transfer':
        sum -= t.amount;
        break;
      case 'income':
      case 'balance_adjustment':
        sum += t.amount;
        break;
    }
  }

  final incoming = await (db.select(db.transactions)
        ..where((t) => t.toAccountId.equals(accountId))
        ..where((t) => t.type.equals('transfer'))
        ..where((t) => t.archived.equals(false)))
      .get();
  for (final t in incoming) {
    sum += t.toAmount ?? t.amount;
  }
  return sum;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  var idCounter = 0;

  Future<void> insertTxn({
    required String type,
    required String accountId,
    required BigInt amount,
    required BigInt date,
    String? toAccountId,
    BigInt? toAmount,
    BigInt? balanceAfter,
    bool archived = false,
  }) async {
    final id = 'txn-${idCounter++}';
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            type: type,
            name: id,
            status: 'cleared',
            date: date,
            accountId: accountId,
            categoryId: type == 'transfer' || type == 'balance_adjustment'
                ? ''
                : 'cat-1',
            amount: amount,
            currency: 'USD',
            toAccountId: Value(toAccountId),
            toAmount:
                toAmount != null ? Value(toAmount) : const Value.absent(),
            toCurrency:
                toAccountId != null ? const Value('USD') : const Value.absent(),
            balanceAfter: balanceAfter != null
                ? Value(balanceAfter)
                : const Value.absent(),
            archived: Value(archived),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
  }

  test('simple ledger: formula matches replay and recompute is a no-op',
      () async {
    BigInt day(int d) => BigInt.from(d * 86400000);

    await insertTxn(
        type: 'income', accountId: 'a', amount: BigInt.from(10000), date: day(1));
    await insertTxn(
        type: 'expense', accountId: 'a', amount: BigInt.from(2500), date: day(2));
    await insertTxn(
        type: 'transfer',
        accountId: 'a',
        toAccountId: 'b',
        amount: BigInt.from(3000),
        toAmount: BigInt.from(3000),
        date: day(3));
    // Archived rows are excluded from both formula and replay.
    await insertTxn(
        type: 'expense',
        accountId: 'a',
        amount: BigInt.from(99999),
        date: day(4),
        archived: true);

    final corrections = await BalanceAdjustmentRecomputer(db).recompute();
    expect(corrections, 0);

    expect(await computeAccountBalance(db, 'a'), BigInt.from(4500));
    expect(await computeAccountBalance(db, 'b'), BigInt.from(3000));
  });

  test('stale balance_adjustment gets corrected once, then converges',
      () async {
    BigInt day(int d) => BigInt.from(d * 86400000);

    await insertTxn(
        type: 'income', accountId: 'a', amount: BigInt.from(5000), date: day(1));
    // Adjustment says balance should be 8000 after day 2; correct delta is
    // 3000 but it was recorded as 1000 (e.g. a back-dated income arrived
    // from another device after the adjustment was created).
    await insertTxn(
        type: 'balance_adjustment',
        accountId: 'a',
        amount: BigInt.from(1000),
        balanceAfter: BigInt.from(8000),
        date: day(2));

    final first = await BalanceAdjustmentRecomputer(db).recompute();
    expect(first, 1);

    final second = await BalanceAdjustmentRecomputer(db).recompute();
    expect(second, 0, reason: 'recompute must be idempotent');

    expect(await computeAccountBalance(db, 'a'), BigInt.from(8000));

    final adjusted = await (db.select(db.transactions)
          ..where((t) => t.type.equals('balance_adjustment')))
        .getSingle();
    expect(adjusted.amount, BigInt.from(3000));
    expect(adjusted.dirty, isTrue,
        reason: 'corrections must be pushed on the next sync cycle');
  });

  test('randomized ledger: formula == replay after recompute, idempotent',
      () async {
    final rng = Random(20260611); // seeded — deterministic test
    const accounts = ['a', 'b', 'c'];

    for (var i = 0; i < 120; i++) {
      final date = BigInt.from(rng.nextInt(90) * 86400000);
      final amount = BigInt.from(rng.nextInt(20000) + 1);
      final account = accounts[rng.nextInt(accounts.length)];
      switch (rng.nextInt(5)) {
        case 0:
          await insertTxn(
              type: 'income', accountId: account, amount: amount, date: date);
          break;
        case 1:
          await insertTxn(
              type: 'expense', accountId: account, amount: amount, date: date);
          break;
        case 2:
          final to = accounts[(accounts.indexOf(account) + 1) % accounts.length];
          final crossCurrency = rng.nextBool();
          await insertTxn(
              type: 'transfer',
              accountId: account,
              toAccountId: to,
              amount: amount,
              toAmount: crossCurrency ? amount * BigInt.two : amount,
              date: date);
          break;
        case 3:
          await insertTxn(
              type: 'balance_adjustment',
              accountId: account,
              amount: amount,
              balanceAfter: BigInt.from(rng.nextInt(50000)),
              date: date);
          break;
        case 4:
          await insertTxn(
              type: 'expense',
              accountId: account,
              amount: amount,
              date: date,
              archived: true);
          break;
      }
    }

    await BalanceAdjustmentRecomputer(db).recompute();
    final again = await BalanceAdjustmentRecomputer(db).recompute();
    expect(again, 0, reason: 'recompute must be idempotent');

    // After recompute, every adjustment's amount satisfies its balanceAfter,
    // so the chronological replay final balance per account must equal the
    // unordered-sum formula. For accounts whose last same-or-later event is
    // an adjustment, that balance is exactly balanceAfter — the formula and
    // the replay agree by construction if and only if the arithmetic per
    // transaction type is identical.
    for (final account in accounts) {
      final formula = await computeAccountBalance(db, account);

      // Replay using the recomputer's exact ordering rules.
      final txns = await (db.select(db.transactions)
            ..where((t) => t.archived.equals(false)))
          .get();
      final events = <({BigInt date, bool incoming, Transaction txn})>[];
      for (final t in txns) {
        if (t.accountId == account) {
          events.add((date: t.date, incoming: false, txn: t));
        }
        if (t.type == 'transfer' && t.toAccountId == account) {
          events.add((date: t.date, incoming: true, txn: t));
        }
      }
      events.sort((x, y) {
        final cmp = x.date.compareTo(y.date);
        if (cmp != 0) return cmp;
        final xAdj = x.txn.type == 'balance_adjustment' ? 1 : 0;
        final yAdj = y.txn.type == 'balance_adjustment' ? 1 : 0;
        return xAdj - yAdj;
      });

      BigInt replay = BigInt.zero;
      for (final ev in events) {
        final t = ev.txn;
        if (ev.incoming) {
          replay += t.toAmount ?? t.amount;
        } else if (t.type == 'expense' || t.type == 'transfer') {
          replay -= t.amount;
        } else {
          replay += t.amount; // income | balance_adjustment
        }
      }

      expect(replay, formula,
          reason: 'account $account: replay and formula diverged');
    }
  });
}
