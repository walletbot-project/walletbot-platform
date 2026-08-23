import 'package:app/data/app_repositories.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('fresh database matches the versioned v3 schema snapshot', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await verifier.migrateAndValidate(
      db,
      3,
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

  test(
    'v2 rows survive the upgrade to v3, which only adds legal_acceptances',
    () async {
      final schema = await verifier.schemaAt(2);
      addTearDown(schema.close);

      schema.rawDatabase.execute(
        'INSERT INTO transactions '
        '(id, type, name, status, date, time_status, account_id, category_id, '
        'amount, currency, created_at, updated_at) '
        "VALUES ('t2', 'expense', 'Almuerzo', 'cleared', 1000, "
        "'approximation', 'a1', 'c1', 750, 'ARS', 10, 20)",
      );
      schema.rawDatabase.execute(
        'INSERT INTO accounts '
        '(id, name, currency, created_at, updated_at) '
        "VALUES ('a1', 'Cuenta', 'ARS', 10, 20)",
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);

      final transactions = await db
          .customSelect(
            'SELECT id, name, amount, time_status FROM transactions',
          )
          .get();
      expect(transactions, hasLength(1));
      expect(transactions.single.read<String>('name'), 'Almuerzo');
      expect(transactions.single.read<int>('amount'), 750);
      // Untouched by the v3 step.
      expect(transactions.single.read<String>('time_status'), 'approximation');

      final accounts = await db
          .customSelect('SELECT id, name FROM accounts')
          .get();
      expect(accounts, hasLength(1));
      expect(accounts.single.read<String>('name'), 'Cuenta');

      // The new table exists and starts empty: an upgrade must never invent an
      // acceptance for a user who was never asked.
      final acceptances = await db.select(db.legalAcceptances).get();
      expect(acceptances, isEmpty);
    },
  );

  test(
    'a v1 database upgrades all the way to v3 in one open',
    () async {
      final schema = await verifier.schemaAt(1);
      addTearDown(schema.close);

      schema.rawDatabase.execute(
        'INSERT INTO transactions '
        '(id, type, name, status, date, account_id, category_id, amount, '
        'currency, created_at, updated_at) '
        "VALUES ('t1', 'income', 'Sueldo', 'cleared', 900, 'a1', 'c1', 1200, "
        "'ARS', 10, 20)",
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);

      // Both steps ran: the v2 column is there with its default AND the v3
      // table exists. A step chain that returned after v2 would fail here.
      final rows = await db
          .customSelect('SELECT id, time_status FROM transactions')
          .get();
      expect(rows.single.read<String>('time_status'), 'none');
      expect(await db.select(db.legalAcceptances).get(), isEmpty);
    },
  );

  test('legal acceptances round-trip their enums and stay append-only', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.legalAcceptances)
        .insert(
          LegalAcceptancesCompanion.insert(
            id: 'acc-1',
            document: LegalDocumentKind.terms,
            version: '2026-08-06',
            acceptedAt: BigInt.from(1000),
            ageConfirmed: const Value(true),
            platform: 'android',
            source: LegalAcceptanceSource.local,
          ),
        );
    await db
        .into(db.legalAcceptances)
        .insert(
          LegalAcceptancesCompanion.insert(
            id: 'acc-2',
            document: LegalDocumentKind.privacy,
            version: '2026-08-06',
            acceptedAt: BigInt.from(2000),
            ageConfirmed: const Value(true),
            platform: 'android',
            source: LegalAcceptanceSource.remote,
          ),
        );

    final rows = await db.select(db.legalAcceptances).get();
    expect(rows, hasLength(2));
    expect(
      rows.map((row) => row.document),
      containsAll(<LegalDocumentKind>[
        LegalDocumentKind.terms,
        LegalDocumentKind.privacy,
      ]),
    );
    expect(rows.every((row) => row.ageConfirmed), isTrue);
    expect(
      rows.singleWhere((row) => row.id == 'acc-2').source,
      LegalAcceptanceSource.remote,
    );
  });

  test('future databases fail instead of being silently downgraded', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (database) => database.execute('PRAGMA user_version = 4'),
      ),
    );
    addTearDown(db.close);

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('Unhandled SQLite migration path: v4 -> v3'),
        ),
      ),
    );
  });
}
