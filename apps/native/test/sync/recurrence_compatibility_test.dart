import 'package:app/database.dart';
import 'package:app/sync/sync_merge.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PullPageMerger merger;
  final row = <String, Object?>{
    'id': 't',
    'type': 'expense',
    'name': 'Rent',
    'status': 'cleared',
    'date': BigInt.from(1000),
    'accountId': 'a',
    'categoryId': 'c',
    'amount': BigInt.from(100),
    'currency': 'ARS',
    'isArchived': false,
    'createdAt': BigInt.one,
    'updatedAt': BigInt.from(10),
    'recurrenceId': 'r',
    'recurrenceIndex': BigInt.zero,
  };
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    merger = PullPageMerger(db);
  });
  tearDown(() async => db.close());

  test('a due occurrence supersedes its legacy visibility tombstone', () async {
    await merger.applyPage(
      rows: [],
      tombstones: [
        {
          'tableName': 'transactions',
          'entityId': 't',
          'deletedAt': BigInt.from(9),
        },
      ],
    );
    await merger.applyPage(
      rows: [
        {'tableName': 'transactions', 'row': row},
      ],
      tombstones: [],
    );
    expect((await db.select(db.transactions).get()).single.recurrenceId, 'r');
    expect(await db.select(db.tombstones).get(), isEmpty);
  });

  test(
    'upgrade replay hydrates series metadata without discarding an offline edit',
    () async {
      await merger.applyPage(
        rows: [
          {'tableName': 'transactions', 'row': row},
        ],
        tombstones: [],
      );
      await db
          .update(db.transactions)
          .write(
            TransactionsCompanion(
              name: const Value('Offline edit'),
              amount: Value(BigInt.from(200)),
              recurrenceId: const Value(null),
              recurrenceIndex: const Value(null),
              dirty: const Value(true),
              updatedAt: Value(BigInt.from(20)),
            ),
          );
      await merger.applyPage(
        rows: [
          {'tableName': 'transactions', 'row': row},
        ],
        tombstones: [],
      );
      final transaction = (await db.select(db.transactions).get()).single;
      expect(transaction.name, 'Offline edit');
      expect(transaction.amount, BigInt.from(200));
      expect(transaction.updatedAt, BigInt.from(20));
      expect(transaction.dirty, isTrue);
      expect(transaction.recurrenceId, 'r');
      expect(transaction.recurrenceIndex, 0);
    },
  );
  test(
    'upgrade replay retains an archived series template after a legacy deletion',
    () async {
      await merger.applyPage(
        rows: [],
        tombstones: [
          {
            'tableName': 'transactions',
            'entityId': 't',
            'deletedAt': BigInt.from(10),
          },
        ],
      );
      await merger.applyPage(
        rows: [
          {
            'tableName': 'transactions',
            'row': {...row, 'isArchived': true},
          },
        ],
        tombstones: [],
      );
      final transaction = (await db.select(db.transactions).get()).single;
      expect(transaction.archived, isTrue);
      expect(transaction.recurrenceId, 'r');
      expect(transaction.dirty, isFalse);
    },
  );
}
