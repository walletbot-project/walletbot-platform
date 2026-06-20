import 'package:app/data/tombstones.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Characterization tests for the tombstone upsert semantics that the sync
// push/merge contract depends on (see LESSONS.md / plan invariant #2):
// - first delete inserts a dirty tombstone
// - repeated deletes bump deletedAt/updatedAt and re-dirty, preserving createdAt
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Tombstone> single() =>
      (db.select(db.tombstones)).getSingle();

  test('first call inserts a dirty tombstone', () async {
    await writeTombstone(db, 'transactions', 'txn-1');

    final row = await single();
    expect(row.entityTable, 'transactions');
    expect(row.entityId, 'txn-1');
    expect(row.dirty, isTrue);
    expect(row.deletedAt, row.createdAt);
    expect(row.updatedAt, row.createdAt);
  });

  test('re-delete bumps deletedAt/updatedAt, re-dirties, keeps createdAt',
      () async {
    await writeTombstone(db, 'tags', 'tag-1');
    final first = await single();

    // Simulate the sync engine acking the tombstone (dirty cleared).
    await (db.update(db.tombstones)).write(
      const TombstonesCompanion(dirty: Value(false)),
    );

    // Ensure the clock advances at millisecond resolution.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await writeTombstone(db, 'tags', 'tag-1');

    final second = await single();
    expect(second.createdAt, first.createdAt);
    expect(second.deletedAt.compareTo(first.deletedAt) > 0, isTrue);
    expect(second.updatedAt.compareTo(first.updatedAt) > 0, isTrue);
    expect(second.dirty, isTrue);
  });

  test('tombstones for different entities do not collide', () async {
    await writeTombstone(db, 'tags', 'shared-id');
    await writeTombstone(db, 'categories', 'shared-id');

    final rows = await db.select(db.tombstones).get();
    expect(rows.length, 2);
  });
}
