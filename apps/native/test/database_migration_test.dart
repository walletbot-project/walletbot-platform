import 'dart:io';

import 'package:app/data/app_repositories.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('AppDatabase migrations', () {
    test(
      'migrates v1 transactions archived column and adds date_confirmed',
      () async {
        final file = await _createLegacyDatabase(
          userVersion: 1,
          useArchivedEverywhere: false,
        );
        addTearDown(() async {
          if (await file.exists()) {
            await file.delete();
          }
        });

        final db = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(db.close);

        final rows = await db
            .customSelect(
              'SELECT is_archived, date_confirmed FROM transactions WHERE id = ?',
              variables: [Variable<String>('txn-v1')],
            )
            .getSingle();

        final transactionColumns = await _columnNames(db, 'transactions');
        expect(transactionColumns.contains('archived'), isFalse);
        expect(transactionColumns.contains('is_archived'), isTrue);
        expect(transactionColumns.contains('date_confirmed'), isTrue);
        expect(rows.read<int>('is_archived'), 1);
        expect(rows.read<int>('date_confirmed'), 1);
        await _expectCurrentSchemaShape(db);
      },
    );

    test('migrates v2 archived columns back to is_archived', () async {
      final file = await _createLegacyDatabase(
        userVersion: 2,
        useArchivedEverywhere: true,
      );
      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      for (final tableName in const [
        'accounts',
        'categories',
        'transactions',
        'tags',
      ]) {
        final columns = await _columnNames(db, tableName);
        expect(columns.contains('archived'), isFalse, reason: tableName);
        expect(columns.contains('is_archived'), isTrue, reason: tableName);
      }

      final account = await db
          .customSelect(
            'SELECT is_archived FROM accounts WHERE id = ?',
            variables: [Variable<String>('acc-v2')],
          )
          .getSingle();
      final transaction = await db
          .customSelect(
            'SELECT is_archived, date_confirmed FROM transactions WHERE id = ?',
            variables: [Variable<String>('txn-v2')],
          )
          .getSingle();

      expect(account.read<int>('is_archived'), 1);
      expect(transaction.read<int>('is_archived'), 1);
      expect(transaction.read<int>('date_confirmed'), 1);
      await _expectCurrentSchemaShape(db);
    });
  });
}

Future<File> _createLegacyDatabase({
  required int userVersion,
  required bool useArchivedEverywhere,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'walletbot_migration_test_',
  );
  final file = File(p.join(directory.path, 'legacy.sqlite'));
  final db = sqlite3.open(file.path);

  final commonArchivedName = useArchivedEverywhere ? 'archived' : 'is_archived';
  db.execute('''
    CREATE TABLE accounts (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      currency TEXT NOT NULL,
      description TEXT,
      color TEXT,
      icon TEXT,
      $commonArchivedName INTEGER NOT NULL DEFAULT 0 CHECK ($commonArchivedName IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
    );
  ''');
  db.execute('''
    CREATE TABLE categories (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      $commonArchivedName INTEGER NOT NULL DEFAULT 0 CHECK ($commonArchivedName IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
    );
  ''');
  db.execute('''
    CREATE TABLE transactions (
      id TEXT NOT NULL PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL,
      date INTEGER NOT NULL,
      account_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      amount INTEGER NOT NULL,
      currency TEXT NOT NULL,
      to_account_id TEXT,
      to_amount INTEGER,
      to_currency TEXT,
      exchange_rate REAL,
      balance_after INTEGER,
      ${useArchivedEverywhere ? 'archived' : 'archived'} INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
    );
  ''');
  db.execute('''
    CREATE TABLE tags (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      parent_id TEXT,
      color TEXT,
      $commonArchivedName INTEGER NOT NULL DEFAULT 0 CHECK ($commonArchivedName IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
    );
  ''');
  db.execute('''
    CREATE TABLE transaction_tags (
      id TEXT NOT NULL PRIMARY KEY,
      transaction_id TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1))
    );
  ''');
  db.execute('''
    CREATE TABLE sync_state (
      id TEXT NOT NULL PRIMARY KEY DEFAULT 'singleton',
      last_server_seq INTEGER NOT NULL DEFAULT 0,
      last_synced_at INTEGER
    );
  ''');
  db.execute('''
    CREATE TABLE tombstones (
      entity_table TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      deleted_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
      PRIMARY KEY (entity_table, entity_id)
    );
  ''');

  db.execute('''
    INSERT INTO accounts (id, name, currency, $commonArchivedName, created_at, updated_at, dirty)
    VALUES ('${userVersion == 1 ? 'acc-v1' : 'acc-v2'}', 'Cuenta', 'ARS', 1, 1, 1, 0);
  ''');
  db.execute('''
    INSERT INTO categories (id, name, $commonArchivedName, created_at, updated_at, dirty)
    VALUES ('${userVersion == 1 ? 'cat-v1' : 'cat-v2'}', 'Comida', 0, 1, 1, 0);
  ''');
  db.execute('''
    INSERT INTO tags (id, name, $commonArchivedName, created_at, updated_at, dirty)
    VALUES ('${userVersion == 1 ? 'tag-v1' : 'tag-v2'}', 'Tag', 0, 1, 1, 0);
  ''');
  db.execute('''
    INSERT INTO transactions (
      id, type, name, status, date, account_id, category_id, amount, currency,
      archived, created_at, updated_at, dirty
    ) VALUES (
      '${userVersion == 1 ? 'txn-v1' : 'txn-v2'}',
      'expense',
      'Cafe',
      'cleared',
      1,
      '${userVersion == 1 ? 'acc-v1' : 'acc-v2'}',
      '${userVersion == 1 ? 'cat-v1' : 'cat-v2'}',
      100,
      'ARS',
      1,
      1,
      1,
      0
    );
  ''');
  db.execute('PRAGMA user_version = $userVersion;');
  db.close();
  return file;
}

Future<Set<String>> _columnNames(AppDatabase db, String tableName) async {
  final rows = await db.customSelect('PRAGMA table_info("$tableName")').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<void> _expectCurrentSchemaShape(AppDatabase db) async {
  for (final tableName in const ['saved_filters', 'dashboard_widgets']) {
    final table = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(tableName)],
        )
        .getSingleOrNull();
    expect(table, isNotNull, reason: '$tableName should exist');
  }

  final syncStateColumns = await _columnNames(db, 'sync_state');
  expect(syncStateColumns.contains('dashboard_seeded'), isTrue);

  final categoryColumns = await _columnNames(db, 'categories');
  expect(categoryColumns.contains('color'), isTrue);
  expect(categoryColumns.contains('icon'), isTrue);

  final account = await db
      .customSelect('SELECT color, icon FROM accounts LIMIT 1')
      .getSingle();
  expect(account.read<String>('color'), kDefaultAccountColor);
  expect(account.read<String>('icon'), kDefaultAccountIcon);

  final category = await db
      .customSelect('SELECT color, icon FROM categories LIMIT 1')
      .getSingle();
  expect(category.read<String>('color'), kDefaultCategoryColor);
  expect(category.read<String>('icon'), kDefaultCategoryIcon);

  final tag = await db
      .customSelect('SELECT color FROM tags LIMIT 1')
      .getSingle();
  expect(tag.read<String>('color'), kDefaultTagColor);

  await _expectTextColumnDefault(db, 'accounts', 'color', kDefaultAccountColor);
  await _expectTextColumnDefault(db, 'accounts', 'icon', kDefaultAccountIcon);
  await _expectTextColumnDefault(
    db,
    'categories',
    'color',
    kDefaultCategoryColor,
  );
  await _expectTextColumnDefault(
    db,
    'categories',
    'icon',
    kDefaultCategoryIcon,
  );
  await _expectTextColumnDefault(db, 'tags', 'color', kDefaultTagColor);

  final repos = AppRepositories(db);
  final newAccountId = await repos.accounts.create(
    name: 'Nueva cuenta',
    currency: 'ARS',
  );
  final newCategoryId = await repos.categories.create(name: 'Nueva categoria');
  final newTagId = await repos.tags.create(name: 'Nuevo tag');

  final newAccount = (await repos.accounts.getById(newAccountId))!;
  expect(newAccount.color, kDefaultAccountColor);
  expect(newAccount.icon, kDefaultAccountIcon);

  final newCategory = (await repos.categories.getById(newCategoryId))!;
  expect(newCategory.color, kDefaultCategoryColor);
  expect(newCategory.icon, kDefaultCategoryIcon);

  final newTag = (await repos.tags.getById(newTagId))!;
  expect(newTag.color, kDefaultTagColor);
}

Future<void> _expectTextColumnDefault(
  AppDatabase db,
  String tableName,
  String columnName,
  String defaultValue,
) async {
  final row = await db
      .customSelect('PRAGMA table_info("$tableName")')
      .get()
      .then(
        (rows) =>
            rows.singleWhere((row) => row.read<String>('name') == columnName),
      );

  expect(row.read<int>('notnull'), 1, reason: '$tableName.$columnName');
  expect(
    row.readNullable<String>('dflt_value'),
    "'$defaultValue'",
    reason: '$tableName.$columnName',
  );
}
