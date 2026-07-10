import 'package:app/data/app_repositories.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart';
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

  test('migrates a legacy v1 database to v3 without dropping data', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: _createLegacyV1Database),
    );
    addTearDown(db.close);

    final account = await db
        .customSelect(
          'SELECT id, name, is_archived, color, icon FROM accounts WHERE id = ?',
          variables: [Variable.withString('acct-1')],
        )
        .getSingle();
    final category = await db
        .customSelect(
          'SELECT id, name, is_archived, color, icon FROM categories WHERE id = ?',
          variables: [Variable.withString('cat-1')],
        )
        .getSingle();
    final transaction = await db
        .customSelect(
          'SELECT id, date_confirmed, is_archived FROM transactions WHERE id = ?',
          variables: [Variable.withString('tx-1')],
        )
        .getSingle();
    final tag = await db
        .customSelect(
          'SELECT id, is_archived, color FROM tags WHERE id = ?',
          variables: [Variable.withString('tag-1')],
        )
        .getSingle();
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('saved_filters', 'dashboard_widgets') ORDER BY name",
        )
        .get();
    final syncStateColumns = await db
        .customSelect('PRAGMA table_info("sync_state")')
        .get();
    expect(account.read<String>('name'), 'Cuenta vieja');
    expect(account.read<int>('is_archived'), 0);
    expect(account.read<String>('color'), kDefaultAccountColor);
    expect(account.read<String>('icon'), kDefaultAccountIcon);
    expect(category.read<String>('name'), 'Categoria vieja');
    expect(category.read<int>('is_archived'), 0);
    expect(category.read<String>('color'), kDefaultCategoryColor);
    expect(category.read<String>('icon'), kDefaultCategoryIcon);
    expect(transaction.read<int>('date_confirmed'), 1);
    expect(transaction.read<int>('is_archived'), 0);
    expect(tag.read<int>('is_archived'), 0);
    expect(tag.read<String>('color'), kDefaultTagColor);
    expect(tables.map((row) => row.read<String>('name')), [
      'dashboard_widgets',
      'saved_filters',
    ]);
    expect(
      syncStateColumns.map((row) => row.read<String>('name')),
      contains('dashboard_seeded'),
    );
  });

  test('migrates a legacy v2 dashboard database to v3', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: _createLegacyV2DashboardDatabase),
    );
    addTearDown(db.close);

    final transactionColumns = await db
        .customSelect('PRAGMA table_info("transactions")')
        .get();
    final accountColumns = await db
        .customSelect('PRAGMA table_info("accounts")')
        .get();
    final savedFilterColumns = await db
        .customSelect('PRAGMA table_info("saved_filters")')
        .get();
    final savedFilter = await db
        .customSelect(
          'SELECT id, name FROM saved_filters WHERE id = ?',
          variables: [Variable.withString('filter-1')],
        )
        .getSingle();
    expect(
      transactionColumns.map((row) => row.read<String>('name')),
      contains('date_confirmed'),
    );
    expect(
      accountColumns.map((row) => row.read<String>('name')),
      contains('is_archived'),
    );
    expect(
      accountColumns.map((row) => row.read<String>('name')),
      isNot(contains('archived')),
    );
    expect(
      savedFilterColumns.map((row) => row.read<String>('name')),
      contains('is_archived'),
    );
    expect(
      savedFilterColumns.map((row) => row.read<String>('name')),
      isNot(contains('archived')),
    );
    expect(savedFilter.read<String>('name'), 'Filtro viejo');
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

void _createLegacyV1Database(dynamic database) {
  _createLegacyBaseSchema(database);
  database
    ..execute('PRAGMA user_version = 1')
    ..execute(
      "INSERT INTO accounts "
      "(id, name, currency, description, color, icon, archived, created_at, "
      "updated_at, dirty) VALUES "
      "('acct-1', 'Cuenta vieja', 'ARS', NULL, NULL, NULL, 0, 1, 1, 0)",
    )
    ..execute(
      "INSERT INTO categories "
      "(id, name, description, archived, created_at, updated_at, dirty) "
      "VALUES ('cat-1', 'Categoria vieja', NULL, 0, 1, 1, 0)",
    )
    ..execute(
      "INSERT INTO transactions "
      "(id, type, name, description, status, date, account_id, category_id, "
      "amount, currency, to_account_id, to_amount, to_currency, "
      "exchange_rate, balance_after, archived, created_at, updated_at, dirty) "
      "VALUES ('tx-1', 'expense', 'Gasto viejo', NULL, 'cleared', 1, "
      "'acct-1', 'cat-1', 1000, 'ARS', NULL, NULL, NULL, NULL, NULL, "
      "0, 1, 1, 0)",
    )
    ..execute(
      "INSERT INTO tags "
      "(id, name, description, parent_id, color, archived, created_at, "
      "updated_at, dirty) VALUES "
      "('tag-1', 'Tag viejo', NULL, NULL, NULL, 0, 1, 1, 0)",
    );
}

void _createLegacyV2DashboardDatabase(dynamic database) {
  _createLegacyBaseSchema(database, includeDashboard: true);
  database
    ..execute('PRAGMA user_version = 2')
    ..execute(
      "INSERT INTO saved_filters "
      "(id, name, config, archived, created_at, updated_at, dirty) VALUES "
      "('filter-1', 'Filtro viejo', '{}', 0, 1, 1, 0)",
    );
}

void _createLegacyBaseSchema(
  dynamic database, {
  bool includeDashboard = false,
}) {
  database
    ..execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        currency TEXT NOT NULL,
        description TEXT NULL,
        color TEXT NULL,
        icon TEXT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute('''
      CREATE TABLE categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT NULL,
        status TEXT NOT NULL,
        date INTEGER NOT NULL,
        account_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        amount INTEGER NOT NULL,
        currency TEXT NOT NULL,
        to_account_id TEXT NULL,
        to_amount INTEGER NULL,
        to_currency TEXT NULL,
        exchange_rate REAL NULL,
        balance_after INTEGER NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute('''
      CREATE TABLE tags (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NULL,
        parent_id TEXT NULL,
        color TEXT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute('''
      CREATE TABLE transaction_tags (
        id TEXT NOT NULL PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
        UNIQUE(transaction_id, tag_id)
      )
    ''')
    ..execute('''
      CREATE TABLE sync_state (
        id TEXT NOT NULL PRIMARY KEY DEFAULT 'singleton',
        last_server_seq INTEGER NOT NULL DEFAULT 0,
        last_synced_at INTEGER NULL
      )
    ''')
    ..execute('''
      CREATE TABLE tombstones (
        entity_table TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
        PRIMARY KEY(entity_table, entity_id)
      )
    ''');

  if (!includeDashboard) return;

  database
    ..execute('''
      CREATE TABLE saved_filters (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        config TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute('''
      CREATE TABLE dashboard_widgets (
        id TEXT NOT NULL PRIMARY KEY,
        type TEXT NOT NULL,
        filter_id TEXT NULL,
        position INTEGER NOT NULL,
        width TEXT NOT NULL,
        options TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
      )
    ''')
    ..execute(
      'ALTER TABLE sync_state ADD COLUMN dashboard_seeded '
      'INTEGER NOT NULL DEFAULT 0 CHECK (dashboard_seeded IN (0, 1))',
    );
}
