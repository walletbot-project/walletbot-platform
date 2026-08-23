import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// Accent defaults. Business rule: every account/category/tag always has a
// color (and accounts/categories an icon). These are the DB-level fallbacks
// applied when a writer omits them; they MIRROR the UI constants in
// components/color_utils.dart and components/{account,category}_icons.dart —
// keep them in sync. Table declarations intentionally repeat these values as
// literals so drift_dev can export self-contained migration helpers; the schema
// test verifies that both representations stay aligned. Color is a hex string;
// icon is a stable icon-name.
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
      text().named('color').withDefault(const Constant('#3B82F6'))();
  TextColumn get icon =>
      text().named('icon').withDefault(const Constant('wallet'))();

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
  TextColumn get color =>
      text().named('color').withDefault(const Constant('#6366F1'))();
  TextColumn get icon =>
      text().named('icon').withDefault(const Constant('category'))();

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

enum TransactionTimeStatus { confirmed, approximation, none }

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
  TextColumn get timeStatus => textEnum<TransactionTimeStatus>()
      .named('time_status')
      .withDefault(const Constant('none'))();
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
      text().named('color').withDefault(const Constant('#69F0AE'))();

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

// A reusable, named slice of transactions (the "Saved View" primitive from
// docs/home-dashboard.md). `config` is an opaque JSON string of the canonical
// `{combinator, children}` condition tree (see
// `TransactionFilter.toCanonicalJson`); the backend never parses it.
@TableIndex(name: 'saved_filters_archived', columns: {#archived})
@TableIndex(name: 'saved_filters_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX saved_filters_needs_sync ON saved_filters (updated_at)
    WHERE dirty = 1;
''')
class SavedFilters extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get config => text().named('config')(); // JSON canonical tree

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

// One configured dashboard tile. `filterId` is a soft reference into
// `saved_filters` (null for the balance card, which carries its currency in
// `options`). `options` is an opaque JSON string (title, aggregation, limit,
// currency); the backend never parses it.
@TableIndex(name: 'dashboard_widgets_position', columns: {#position})
@TableIndex(name: 'dashboard_widgets_archived', columns: {#archived})
@TableIndex(name: 'dashboard_widgets_updated_at', columns: {#updatedAt})
@TableIndex.sql('''
  CREATE INDEX dashboard_widgets_needs_sync ON dashboard_widgets (updated_at)
    WHERE dirty = 1;
''')
class DashboardWidgets extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get type => text().named('type')(); // "stat" | "list" | "balance"
  TextColumn get filterId => text().named('filter_id').nullable()();
  IntColumn get position => integer().named('position')();
  TextColumn get width => text().named('width')(); // "full" | "half" | "third"
  TextColumn get options => text().named('options')(); // JSON display options

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

// Singleton — tracks the highest server-side seq the client has pulled.
class SyncState extends Table {
  TextColumn get id =>
      text().named('id').withDefault(const Constant('singleton'))();
  Int64Column get lastServerSeq =>
      int64().named('last_server_seq').withDefault(Constant(BigInt.zero))();
  Int64Column get lastSyncedAt => int64().named('last_synced_at').nullable()();
  // One-time guard so the default dashboard is seeded at most once per device
  // (see DashboardRepository.seedDefaultIfEmpty).
  BoolColumn get dashboardSeeded =>
      boolean().named('dashboard_seeded').withDefault(const Constant(false))();

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

// Append-only log for Gemini Live conversations. These tables deliberately do
// not participate in the financial entity sync: voice traffic is high churn,
// has different retention/privacy characteristics, and is replicated through
// its own bounded event batches.
@TableIndex(name: 'voice_sessions_status', columns: {#status})
@TableIndex(name: 'voice_sessions_updated_at', columns: {#updatedAt})
class VoiceSessions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get model => text().named('model')();
  TextColumn get status => text().named('status')();
  Int64Column get startedAt => int64().named('started_at')();
  Int64Column get updatedAt => int64().named('updated_at')();
  Int64Column get endedAt => int64().named('ended_at').nullable()();
  BoolColumn get endedExplicitly =>
      boolean().named('ended_explicitly').withDefault(const Constant(false))();
  TextColumn get resumeHandle => text().named('resume_handle').nullable()();
  Int64Column get resumeHandleUpdatedAt =>
      int64().named('resume_handle_updated_at').nullable()();
  BoolColumn get remoteEnabled =>
      boolean().named('remote_enabled').withDefault(const Constant(false))();
  BoolColumn get remoteSynced =>
      boolean().named('remote_synced').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'voice_events_session_id', columns: {#sessionId})
@TableIndex(name: 'voice_events_remote_synced', columns: {#remoteSynced})
class VoiceSessionEvents extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get sessionId => text().named('session_id')();
  IntColumn get sequence => integer().named('sequence')();
  Int64Column get occurredAt => int64().named('occurred_at')();
  TextColumn get type => text().named('type')();
  TextColumn get direction => text().named('direction')();
  TextColumn get modality => text().named('modality').nullable()();
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get rawJson => text().named('raw_json').nullable()();
  BlobColumn get binaryData => blob().named('binary_data').nullable()();
  TextColumn get binaryMimeType =>
      text().named('binary_mime_type').nullable()();
  BoolColumn get remoteSynced =>
      boolean().named('remote_synced').withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, sequence},
  ];
}

/// Which legal document an acceptance row refers to. Mirrors
/// `LEGAL_DOCUMENTS` in `packages/shared/src/legal.ts`.
enum LegalDocumentKind { terms, privacy }

/// Where an acceptance row came from.
///
/// [local] is the user ticking the boxes on this device — the only record that
/// exists for a local-only account. [remote] is the backend's row mirrored
/// down for a remote account, so the gate can answer offline; the backend
/// stays authoritative for those.
enum LegalAcceptanceSource { local, remote }

/// Append-only record of Terms & Conditions / Privacy Policy acceptances.
///
/// Deliberately NOT synced: it is absent from the sync engine's table list and
/// from the backend's `SYNCED_TABLES`, so the wire format is unchanged (no
/// `minSupportedVersion` bump). Remote acceptances travel through
/// `v1/legal/mutations:accept` instead; this table is the local-account record
/// of truth and, for remote accounts, an offline mirror.
@TableIndex(
  name: 'legal_acceptances_document_version',
  columns: {#document, #version},
)
class LegalAcceptances extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get document =>
      textEnum<LegalDocumentKind>().named('document')();
  // Ordered opaque string (e.g. '2026-08-06'), compared lexicographically.
  TextColumn get version => text().named('version')();
  Int64Column get acceptedAt => int64().named('accepted_at')();
  // The 18+ representation made alongside this acceptance.
  BoolColumn get ageConfirmed =>
      boolean().named('age_confirmed').withDefault(const Constant(false))();
  TextColumn get platform => text().named('platform')();
  TextColumn get appVersion => text().named('app_version').nullable()();
  TextColumn get locale => text().named('locale').nullable()();
  TextColumn get source => textEnum<LegalAcceptanceSource>().named('source')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Tags,
    TransactionTags,
    SavedFilters,
    DashboardWidgets,
    SyncState,
    Tombstones,
    VoiceSessions,
    VoiceSessionEvents,
    LegalAcceptances,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase.forUser(String userId)
    : super(_openConnection(_dbNameFor(userId))) {
    debugPrint('sqlite: constructing user database');
  }

  /// Test-only constructor backed by an arbitrary executor (e.g.
  /// `NativeDatabase.memory()`). Production code must use [AppDatabase.forUser].
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Anything below the v1 baseline, a downgrade, or a version this build
      // has never heard of must fail loudly rather than be guessed at.
      if (from < 1 || from > to || to > 3) {
        throw UnsupportedError(
          'Unhandled SQLite migration path: v$from -> v$to. '
          'Define an explicit upgrade path in AppDatabase.migration.',
        );
      }
      // Steps are cumulative and must stay that way: a v1 database upgrading
      // straight to v3 runs both. (The previous single-step form returned
      // early after v2, which would have skipped everything after it.)
      //
      // v2: approximate/confirmed timing metadata on transactions.
      if (from < 2) {
        await m.addColumn(transactions, transactions.timeStatus);
      }
      // v3: local record of Terms/Privacy acceptances. A new table only —
      // existing rows are untouched. `createTable` does not carry the
      // `@TableIndex` declarations with it, so the index is created
      // explicitly; without it the upgraded schema diverges from a fresh
      // install (the snapshot test catches exactly that).
      if (from < 3) {
        await m.createTable(legalAcceptances);
        await m.create(legalAcceptancesDocumentVersion);
      }
    },
    beforeOpen: (details) async {
      final userVersion = await customSelect('PRAGMA user_version').getSingle();
      debugPrint(
        'sqlite: opening user database versionBefore=${details.versionBefore} '
        'versionNow=${details.versionNow} wasCreated=${details.wasCreated} '
        'hadUpgrade=${details.hadUpgrade} pragmaUserVersionBeforeFinalize='
        '${userVersion.read<int>('user_version')}',
      );
    },
  );

  static String _dbNameFor(String userId) => 'app_database_$userId';

  static QueryExecutor _openConnection(String name) {
    return driftDatabase(
      name: name,
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
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
