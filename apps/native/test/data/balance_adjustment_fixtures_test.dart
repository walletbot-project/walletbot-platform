// The Dart half of the balance-adjustment parity suite. The same fixture
// table runs against the TS reference in
// packages/shared/test/balance-adjustment.test.ts and the backend's
// incremental reconciliation in
// packages/backend/convex/transactions/adjustments.test.ts — a behavioural
// change on one side fails the others until all are updated together.

import 'dart:convert';
import 'dart:io';

import 'package:app/data/balance_adjustments.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerEntry _entryOf(Map<String, Object?> raw) => LedgerEntry(
  id: raw['id']! as String,
  type: raw['type']! as String,
  accountId: raw['accountId']! as String,
  toAccountId: raw['toAccountId'] as String?,
  amount: BigInt.from(raw['amount']! as int),
  toAmount: raw['toAmount'] == null
      ? null
      : BigInt.from(raw['toAmount']! as int),
  balanceAfter: raw['balanceAfter'] == null
      ? null
      : BigInt.from(raw['balanceAfter']! as int),
  date: BigInt.from(raw['date']! as int),
  createdAt: BigInt.from(raw['createdAt']! as int),
  archived: (raw['isArchived'] as bool?) ?? false,
);

void main() {
  // flutter test runs with cwd = apps/native.
  final fixtures =
      jsonDecode(
            File(
              '../../packages/shared/src/balance-adjustment-fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final cases = [
    for (final raw in fixtures['cases']! as List)
      (
        name: (raw as Map<String, Object?>)['name']! as String,
        entries: [
          for (final e in raw['entries']! as List)
            _entryOf(e as Map<String, Object?>),
        ],
        expected: {
          for (final MapEntry(:key, :value)
              in (raw['expected']! as Map<String, Object?>).entries)
            key: BigInt.from(value! as int),
        },
      ),
  ];

  group('reconcileAdjustments matches the shared fixtures', () {
    for (final c in cases) {
      test(c.name, () {
        expect(reconcileAdjustments(c.entries), c.expected);
      });
    }
  });

  group('reconcileLocalAdjustments writes the shared fixtures', () {
    for (final c in cases) {
      test(c.name, () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        for (final e in c.entries) {
          await db
              .into(db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  id: e.id,
                  type: e.type,
                  name: e.id,
                  status: 'cleared',
                  date: e.date,
                  accountId: e.accountId,
                  categoryId: '',
                  amount: e.amount,
                  currency: 'ARS',
                  toAccountId: Value(e.toAccountId),
                  toAmount: Value(e.toAmount),
                  balanceAfter: Value(e.balanceAfter),
                  archived: Value(e.archived),
                  createdAt: e.createdAt,
                  updatedAt: e.createdAt,
                ),
              );
        }

        await reconcileLocalAdjustments(db);

        final rows = await (db.select(
          db.transactions,
        )..where((t) => t.id.isIn(c.expected.keys))).get();
        expect({for (final r in rows) r.id: r.amount}, c.expected);
        expect(
          await reconcileLocalAdjustments(db),
          0,
          reason: 'reconciling twice must be a no-op',
        );
      });
    }
  });
}
