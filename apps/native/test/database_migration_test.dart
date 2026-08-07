import 'package:app/data/app_repositories.dart';
import 'package:app/database.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('fresh database matches the versioned v2 schema snapshot', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await verifier.migrateAndValidate(
      db,
      2,
      options: const ValidationOptions(validateDropped: true),
    );
  });

  test(
    'schema default values stay aligned with application constants',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repositories = AppRepositories(db);

      final accountId = await repositories.accounts.create(
        name: 'Cuenta',
        currency: 'ARS',
      );
      final categoryId = await repositories.categories.create(name: 'Comida');
      final tagId = await repositories.tags.create(name: 'Trabajo');

      final account = (await repositories.accounts.getById(accountId))!;
      final category = (await repositories.categories.getById(categoryId))!;
      final tag = (await repositories.tags.getById(tagId))!;

      expect(account.color, kDefaultAccountColor);
      expect(account.icon, kDefaultAccountIcon);
      expect(category.color, kDefaultCategoryColor);
      expect(category.icon, kDefaultCategoryIcon);
      expect(tag.color, kDefaultTagColor);
    },
  );

  test(
    'v1 rows survive the upgrade to v2 and default time_status to none',
    () async {
      final schema = await verifier.schemaAt(1);
      addTearDown(schema.close);

      // Insert a realistic transaction using the v1 schema (no time_status
      // column yet) directly on the raw database backing the connection.
      schema.rawDatabase.execute(
        'INSERT INTO transactions '
        '(id, type, name, status, date, account_id, category_id, amount, '
        'currency, created_at, updated_at) '
        "VALUES ('t1', 'expense', 'Café', 'cleared', 1000, 'a1', 'c1', 500, "
        "'ARS', 10, 20)",
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      final rows = await db
          .customSelect(
            'SELECT id, name, amount, date_confirmed, time_status '
            'FROM transactions',
          )
          .get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.read<String>('id'), 't1');
      expect(row.read<String>('name'), 'Café');
      expect(row.read<int>('amount'), 500);
      // Existing default preserved.
      expect(row.read<int>('date_confirmed'), 1);
      // New column backfilled with its declared default.
      expect(row.read<String>('time_status'), 'none');
    },
  );

  test('future databases fail instead of being silently downgraded', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (database) => database.execute('PRAGMA user_version = 3'),
      ),
    );
    addTearDown(db.close);

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('Unhandled SQLite migration path: v3 -> v2'),
        ),
      ),
    );
  });
}
