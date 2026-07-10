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

  test('fresh database matches the published v1 schema snapshot', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await verifier.migrateAndValidate(
      db,
      1,
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
    'pre-baseline databases fail instead of being silently downgraded',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (database) => database.execute('PRAGMA user_version = 2'),
        ),
      );
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('No SQLite migration is registered for v2 -> v1'),
          ),
        ),
      );
    },
  );
}
