import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@TableIndex(name: 'accounts_archived', columns: {#archived})
@TableIndex(name: 'accounts_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX accounts_needs_sync ON accounts (updated_at)
    WHERE dirty = 1;
''')
class Accounts extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get currency => text().named('currency')();
  TextColumn get description => text().named('description').nullable()();
  TextColumn get color => text().named('color').nullable()(); // hex color code
  TextColumn get icon => text().named('icon').nullable()(); // from defined list

  BoolColumn get archived => boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'categories_archived', columns: {#archived})
@TableIndex(name: 'categories_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX categories_needs_sync ON categories (updated_at)
    WHERE dirty = 1;
''')
class Categories extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get description => text().named('description').nullable()();

  BoolColumn get archived => boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'transactions_account_id', columns: {#accountId})
@TableIndex(name: 'transactions_category_id', columns: {#categoryId})
@TableIndex(name: 'transactions_to_account_id', columns: {#toAccountId})
@TableIndex(name: 'transactions_date', columns: {#date})
@TableIndex(name: 'transactions_status', columns: {#status})
@TableIndex(name: 'transactions_type', columns: {#type})
@TableIndex(name: 'transactions_archived', columns: {#archived})
@TableIndex(name: 'transactions_updated_at', columns: {#updatedAt})
@TableIndex(name: 'transactions_account_id_date', columns: {#accountId, #date})
@TableIndex(name: 'transactions_category_id_date', columns: {#categoryId, #date})
@TableIndex.sql('''
  CREATE INDEX transactions_needs_sync ON transactions (updated_at)
    WHERE dirty = 1;
''')
class Transactions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get type => text().named('type')(); //  "expense" | "income" | "transfer" | "balance_adjustment"
  TextColumn get name => text().named('name')();
  TextColumn get description => text().named('description').nullable()();
  TextColumn get status => text().named('status')(); // "pending" | "cleared"
  Int64Column get date => int64().named('date')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get categoryId => text().named('category_id')();
  Int64Column get amount => int64().named('amount')(); // cents
  TextColumn get currency => text().named('currency')();
  BoolColumn get dateConfirmed => boolean()
      .named('date_confirmed')
      .withDefault(const Constant(true))(); // si gaston registra el gasto no sabe si el día que se lo decis es el día que paso o no.

  TextColumn get toAccountId => text().named('to_account_id').nullable()(); // for transfers
  Int64Column get toAmount => int64().named('to_amount').nullable()(); // for transfers
  TextColumn get toCurrency => text().named('to_currency').nullable()(); // for transfers
  RealColumn get exchangeRate => real().named('exchange_rate').nullable()(); // for transfers

  Int64Column get balanceAfter => int64().named('balance_after').nullable()(); // cents, for balance adjustments

  BoolColumn get archived =>
      boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'tags_parent_id', columns: {#parentId})
@TableIndex(name: 'tags_archived', columns: {#archived})
@TableIndex(name: 'tags_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX tags_needs_sync ON tags (updated_at)
    WHERE dirty = 1;
''')
class Tags extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get description => text().named('description').nullable()();
  TextColumn get parentId => text().named('parent_id').nullable()();
  TextColumn get color => text().named('color').nullable()(); // hex color code

  BoolColumn get archived => boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'transaction_tags_transaction_id', columns: {#transactionId})
@TableIndex(name: 'transaction_tags_tag_id', columns: {#tagId})
@TableIndex(name: 'transaction_tags_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX transaction_tags_needs_sync ON transaction_tags (updated_at)
    WHERE dirty = 1;
''')
class TransactionTags extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get transactionId => text().named('transaction_id')();
  TextColumn get tagId => text().named('tag_id')();

  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {transactionId, tagId},
  ];
}

// Singleton — tracks the highest server-side seq the client has pulled.
class SyncState extends Table {
  TextColumn get id => text().named('id').withDefault(const Constant('singleton'))();
  Int64Column get lastServerSeq => int64().named('last_server_seq').withDefault(Constant(BigInt.zero))();
  Int64Column get lastSyncedAt => int64().named('last_synced_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// Soft-delete record so deletes flow through sync. PK is the natural key
// `(entity_table, entity_id)`.
@TableIndex(name: 'tombstones_entity_table', columns: {#entityTable})
@TableIndex(name: 'tombstones_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX tombstones_needs_sync ON tombstones (updated_at)
    WHERE dirty = 1;
''')
class Tombstones extends Table {
  TextColumn get entityTable => text().named('entity_table')();
  TextColumn get entityId => text().named('entity_id')();
  Int64Column get deletedAt => int64().named('deleted_at')();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty => boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {entityTable, entityId};
}

@DriftDatabase(tables: [Accounts, Categories, Transactions, Tags, TransactionTags, SyncState, Tombstones])
class AppDatabase extends _$AppDatabase {
  AppDatabase.forUser(String userId) : super(_openConnection(_dbNameFor(userId)));
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 3) {
        await _migrateToV3(m);
      }
    },
  );

  static String _dbNameFor(String userId) => 'app_database_$userId';

  static QueryExecutor _openConnection(String name) {
    return driftDatabase(
      name: name,
      native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
    );
  }

  Future<void> _migrateToV3(Migrator m) async {
    for (final tableName in const [
      'accounts',
      'categories',
      'transactions',
      'tags',
    ]) {
      await _renameArchivedColumnIfNeeded(tableName);
    }

    final transactionColumns = await _columnNames('transactions');
    if (!transactionColumns.contains('date_confirmed')) {
      await m.addColumn(transactions, transactions.dateConfirmed);
    }
  }

  Future<void> _renameArchivedColumnIfNeeded(String tableName) async {
    final columns = await _columnNames(tableName);
    if (!columns.contains('archived') || columns.contains('is_archived')) {
      return;
    }

    await customStatement(
      'ALTER TABLE "$tableName" RENAME COLUMN "archived" TO "is_archived"',
    );
  }

  Future<Set<String>> _columnNames(String tableName) async {
    final rows = await customSelect('PRAGMA table_info("$tableName")').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Stream<List<Account>> watchAccounts() =>
      (select(accounts)
            ..where((a) => a.archived.equals(false))
            ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]))
          .watch();

  Future<void> insertAccount({required String id, required String name, required String currency}) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return into(
      accounts,
    ).insert(AccountsCompanion.insert(id: id, name: name, currency: currency, createdAt: now, updatedAt: now, dirty: const Value(true)));
  }

  Future<void> insertTransaction({
    required String id,
    required String type,
    required String name,
    required String status,
    required BigInt date,
    required String accountId,
    required String categoryId,
    required BigInt amount,
    required String currency,
    BigInt? balanceAfter,
  }) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return into(transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        type: type,
        name: name,
        status: status,
        date: date,
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        currency: currency,
        balanceAfter: balanceAfter != null ? Value(balanceAfter) : const Value.absent(),
        createdAt: now,
        updatedAt: now,
        dirty: const Value(true),
      ),
    );
  }

  static Future<void> deleteForUser(String userId) async {
    final dir = await getApplicationSupportDirectory();
    final base = p.join(dir.path, '${_dbNameFor(userId)}.sqlite');
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$base$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}
