import 'package:app/database.dart';
import 'package:app/sync/unsynced.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a freshly created database has nothing to push', () async {
    expect(await hasUnsyncedChanges(db), isFalse);
  });

  test('a clean row is not unsynced work', () async {
    await db.customStatement(
      "INSERT INTO accounts (id, name, currency, created_at, updated_at, dirty)"
      " VALUES ('a', 'Cash', 'USD', 0, 0, 0)",
    );

    expect(await hasUnsyncedChanges(db), isFalse);
  });

  test('a dirty row in any synced table counts', () async {
    // One per table, checked in isolation: a probe that silently skipped a
    // table would let that table's writes be signed away without a warning.
    const inserts = {
      'accounts':
          "INSERT INTO accounts (id, name, currency, created_at, updated_at,"
          " dirty) VALUES ('a', 'Cash', 'USD', 0, 0, 1)",
      'categories':
          "INSERT INTO categories (id, name, created_at, updated_at, dirty)"
          " VALUES ('c', 'Food', 0, 0, 1)",
      'transactions':
          "INSERT INTO transactions (id, type, name, status, date,"
          " account_id, category_id, amount, currency, created_at,"
          " updated_at, dirty) VALUES ('t', 'expense', 'Lunch',"
          " 'cleared', 0, 'a', 'c', 100, 'USD', 0, 0, 1)",
      'tags':
          "INSERT INTO tags (id, name, created_at, updated_at, dirty)"
          " VALUES ('g', 'Work', 0, 0, 1)",
      'transaction_tags':
          "INSERT INTO transaction_tags (id, transaction_id, tag_id,"
          " created_at, updated_at, dirty) VALUES ('j', 't', 'g', 0, 0, 1)",
      'saved_filters':
          "INSERT INTO saved_filters (id, name, config, created_at,"
          " updated_at, dirty) VALUES ('f', 'Mine', '{}', 0, 0, 1)",
      'dashboard_widgets':
          "INSERT INTO dashboard_widgets (id, type, position, width, options,"
          " created_at, updated_at, dirty) VALUES ('w', 'stat', 0, 'full',"
          " '{}', 0, 0, 1)",
      'tombstones':
          "INSERT INTO tombstones (entity_table, entity_id, deleted_at,"
          " created_at, updated_at, dirty) VALUES ('accounts', 'gone', 0,"
          " 0, 0, 1)",
    };

    for (final entry in inserts.entries) {
      final scoped = AppDatabase.forTesting(NativeDatabase.memory());
      await scoped.customStatement(entry.value);
      final unsynced = await hasUnsyncedChanges(scoped);
      // Closed before the next one opens: two live AppDatabase instances trip
      // drift's multiple-instance warning.
      await scoped.close();

      expect(
        unsynced,
        isTrue,
        reason: 'a dirty ${entry.key} row must count as unsynced work',
      );
    }
  });

  test(
    'markAllSyncedTablesDirty flags clean rows so a first push sends them',
    () async {
      await db.customStatement(
        "INSERT INTO accounts (id, name, currency, created_at, updated_at, dirty)"
        " VALUES ('a', 'Cash', 'USD', 0, 0, 0)",
      );
      await db.customStatement(
        "INSERT INTO categories (id, name, created_at, updated_at, dirty)"
        " VALUES ('c', 'Food', 0, 0, 0)",
      );
      expect(await hasUnsyncedChanges(db), isFalse);

      await markAllSyncedTablesDirty(db);

      expect(await hasUnsyncedChanges(db), isTrue);
      final clean = await db
          .customSelect(
            'SELECT (SELECT COUNT(*) FROM accounts WHERE dirty = 0)'
            ' + (SELECT COUNT(*) FROM categories WHERE dirty = 0) AS n',
          )
          .getSingle();
      expect(clean.read<int>('n'), 0);
    },
  );
}
