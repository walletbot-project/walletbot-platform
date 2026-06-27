import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// Accent defaults. Business rule: every account/category/tag always has a
// color (and accounts/categories an icon). These are the DB-level fallbacks
// applied when a writer omits them; they MIRROR the UI constants in
// components/color_utils.dart and components/{account,category}_icons.dart —
// keep them in sync. Color is a hex string; icon is a stable icon-name.
const String kDefaultAccountColor = '#3B82F6';
const String kDefaultAccountIcon = 'wallet';
const String kDefaultCategoryColor = '#6366F1';
const String kDefaultCategoryIcon = 'category';
const String kDefaultTagColor = '#69F0AE';

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
  // Always defined (business rule): non-null with a DB default.
  TextColumn get color =>
      text().named('color').withDefault(const Constant(kDefaultAccountColor))();
  TextColumn get icon =>
      text().named('icon').withDefault(const Constant(kDefaultAccountIcon))();

  BoolColumn get archived =>
      boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

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
  // Always defined (business rule): non-null with a DB default.
  TextColumn get color => text()
      .named('color')
      .withDefault(const Constant(kDefaultCategoryColor))();
  TextColumn get icon =>
      text().named('icon').withDefault(const Constant(kDefaultCategoryIcon))();

  BoolColumn get archived =>
      boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

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
@TableIndex(
  name: 'transactions_category_id_date',
  columns: {#categoryId, #date},
)
@TableIndex.sql('''
  CREATE INDEX transactions_needs_sync ON transactions (updated_at)
    WHERE dirty = 1;
''')
class Transactions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get type => text().named(
    'type',
  )(); //  "expense" | "income" | "transfer" | "balance_adjustment"
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
      .withDefault(
        const Constant(true),
      )(); // si gaston registra el gasto no sabe si el día que se lo decis es el día que paso o no.

  TextColumn get toAccountId =>
      text().named('to_account_id').nullable()(); // for transfers
  Int64Column get toAmount =>
      int64().named('to_amount').nullable()(); // for transfers
  TextColumn get toCurrency =>
      text().named('to_currency').nullable()(); // for transfers
  RealColumn get exchangeRate =>
      real().named('exchange_rate').nullable()(); // for transfers

  Int64Column get balanceAfter => int64()
      .named('balance_after')
      .nullable()(); // cents, for balance adjustments

  BoolColumn get archived =>
      boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

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
  // Always defined (business rule): non-null with a DB default.
  TextColumn get color =>
      text().named('color').withDefault(const Constant(kDefaultTagColor))();

  BoolColumn get archived =>
      boolean().named('is_archived').withDefault(const Constant(false))();
  Int64Column get createdAt => int64().named('created_at')();
  Int64Column get updatedAt => int64().named('updated_at')();

  // Sync
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

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
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {transactionId, tagId},
  ];
}

// Singleton — tracks the highest server-side seq the client has pulled.
class SyncState extends Table {
  TextColumn get id =>
      text().named('id').withDefault(const Constant('singleton'))();
  Int64Column get lastServerSeq =>
      int64().named('last_server_seq').withDefault(Constant(BigInt.zero))();
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
  BoolColumn get dirty =>
      boolean().named('dirty').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {entityTable, entityId};
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Tags,
    TransactionTags,
    SyncState,
    Tombstones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase.forUser(String userId)
    : super(_openConnection(_dbNameFor(userId)));

  /// Test-only constructor backed by an arbitrary executor (e.g.
  /// `NativeDatabase.memory()`). Production code must use [AppDatabase.forUser].
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static String _dbNameFor(String userId) => 'app_database_$userId';

  static QueryExecutor _openConnection(String name) {
    return driftDatabase(
      name: name,
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  Stream<List<Account>> watchAccounts() =>
      (select(accounts)
            ..where((a) => a.archived.equals(false))
            ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]))
          .watch();

  Future<void> insertAccount({
    required String id,
    required String name,
    required String currency,
  }) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return into(accounts).insert(
      AccountsCompanion.insert(
        id: id,
        name: name,
        currency: currency,
        createdAt: now,
        updatedAt: now,
        dirty: const Value(true),
      ),
    );
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
        balanceAfter: balanceAfter != null
            ? Value(balanceAfter)
            : const Value.absent(),
        createdAt: now,
        updatedAt: now,
        dirty: const Value(true),
      ),
    );
  }

  // ── Read helpers ──────────────────────────────────────────────────────────

  Future<Transaction?> getTransaction(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Account?> getAccount(String id) =>
      (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<Category?> getCategory(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<Category>> listActiveCategories() =>
      (select(categories)
            ..where((c) => c.archived.equals(false))
            ..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .get();

  // ── Patch helpers (used by voice action widget edit forms) ─────────────────

  Future<void> patchTransaction(
    String id, {
    required String name,
    required BigInt date,
    BigInt? amount,
    String? categoryId,
    String? description,
    String? status,
  }) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        name: Value(name),
        date: Value(date),
        amount: amount != null ? Value(amount) : const Value.absent(),
        categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
        description: Value(description),
        status: status != null ? Value(status) : const Value.absent(),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> patchAccount(
    String id, {
    required String name,
    String? description,
  }) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        description: Value(description),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> patchCategory(
    String id, {
    required String name,
    String? description,
  }) {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        description: Value(description),
        updatedAt: Value(now),
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
