import 'package:drift/drift.dart';

import '../../database.dart';
import '../occurrence.dart';
import '../ids.dart';
import '../models/entity_counts.dart';
import 'repository_base.dart';

/// Reads and writes for transaction categories.
class CategoryRepository extends RepositoryBase {
  CategoryRepository(super.db);

  /// The user's order: positioned rows by `position`, then the rest (never
  /// reordered, or created since) by creation. Mirrors `compareByPosition` in
  /// @wallet-bot/shared and the SQL in [watchWithCounts] — keep them in
  /// lockstep.
  static List<OrderClauseGenerator<$CategoriesTable>> get _userOrder => [
    (c) => OrderingTerm(expression: c.position.isNull()),
    (c) => OrderingTerm(expression: c.position),
    (c) => OrderingTerm(expression: c.createdAt),
  ];

  /// Active categories in the user's order.
  Stream<List<Category>> watchActive() =>
      (db.select(db.categories)
            ..where((c) => c.archived.equals(false))
            ..orderBy(_userOrder))
          .watch();

  /// Live list, active-only by default, in the user's order.
  Stream<List<Category>> watchAll({bool includeArchived = false}) {
    final query = db.select(db.categories)..orderBy(_userOrder);
    if (!includeArchived) {
      query.where((c) => c.archived.equals(false));
    }
    return query.watch();
  }

  /// One-shot list, active-only by default, in the user's order.
  Future<List<Category>> listAll({bool includeArchived = false}) {
    final query = db.select(db.categories)..orderBy(_userOrder);
    if (!includeArchived) {
      query.where((c) => c.archived.equals(false));
    }
    return query.get();
  }

  /// Alias of [listAll] with the default scope, for readable call sites.
  Future<List<Category>> listActive() => listAll();

  /// Exact-id lookup; finds archived categories too. Null when missing.
  Future<Category?> getById(String id) => (db.select(
    db.categories,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Active categories with their transaction counts, in the user's order. The
  /// `readsFrom` set is what keeps the count live when sync merges land —
  /// keep it in lockstep with the SQL.
  Stream<List<CategoryWithCount>> watchWithCounts() {
    final query = db.customSelect(
      '''
        SELECT c.id, c.name, c.description, c.color, c.icon, c.position,
               c.is_archived, c.created_at, c.updated_at, c.dirty,
               COUNT(t.id) AS transaction_count
        FROM categories c
        LEFT JOIN transactions t
               ON t.category_id = c.id
              AND t.is_archived = 0
              AND t.date < $pastCutoffSql
        WHERE c.is_archived = 0
        GROUP BY c.id, c.name, c.description, c.color, c.icon, c.position,
                 c.is_archived, c.created_at, c.updated_at, c.dirty
        ORDER BY c.position IS NULL, c.position, c.created_at
      ''',
      readsFrom: {db.categories, db.transactions},
    );

    return query.watch().map((rows) {
      return rows.map((row) {
        return CategoryWithCount(
          category: Category(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            description: row.readNullable<String>('description'),
            color: row.read<String>('color'),
            icon: row.read<String>('icon'),
            position: row.readNullable<int>('position'),
            archived: row.read<bool>('is_archived'),
            createdAt: row.read<BigInt>('created_at'),
            updatedAt: row.read<BigInt>('updated_at'),
            dirty: row.read<bool>('dirty'),
          ),
          transactionCount: row.read<int>('transaction_count'),
        );
      }).toList();
    });
  }

  /// Live total spent (expenses only) in a category within `[fromMs,
  /// toExclusiveMs)`, grouped by transaction currency. Computed with a SQL
  /// `SUM` aggregate (not by loading rows), and re-emits when transactions
  /// change. Transfers, income and balance adjustments are excluded.
  Stream<Map<String, BigInt>> watchSpendByCurrency(
    String categoryId, {
    required BigInt fromMs,
    required BigInt toExclusiveMs,
  }) {
    final currency = db.transactions.currency;
    final total = db.transactions.amount.sum();
    final query = db.selectOnly(db.transactions)
      ..addColumns([currency, total])
      ..where(
        db.transactions.archived.equals(false) &
            db.transactions.categoryId.equals(categoryId) &
            db.transactions.type.equals('expense') &
            db.transactions.date.isBiggerOrEqualValue(fromMs) &
            db.transactions.date.isSmallerThanValue(toExclusiveMs) &
            db.transactions.date.isSmallerThan(pastCutoffExpression()),
      )
      ..groupBy([currency]);

    return query.watch().map((rows) {
      final result = <String, BigInt>{};
      for (final row in rows) {
        final cur = row.read(currency);
        final sum = row.read(total);
        if (cur != null && sum != null) result[cur] = sum;
      }
      return result;
    });
  }

  /// Creates a category and returns its new id.
  Future<String> create({
    required String name,
    String? description,
    String? color,
    String? icon,
  }) async {
    final id = newUuid();
    final now = currentMs;
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
            color: Value.absentIfNull(color),
            icon: Value.absentIfNull(icon),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    return id;
  }

  /// Partial update via `Value<T>` (absent = keep, `Value(null)` = clear).
  /// Always bumps `updatedAt` and re-dirties.
  Future<void> update(
    String id, {
    Value<String> name = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String> color = const Value.absent(),
    Value<String> icon = const Value.absent(),
  }) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: name,
        description: description,
        color: color,
        icon: icon,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
  }

  /// Persists the user's order: `position = index` for each id, in one
  /// transaction. Rows already at their index are left alone, so a drag only
  /// re-dirties (and syncs) the categories that actually moved.
  Future<void> reorder(List<String> idsInOrder) async {
    final now = currentMs;
    await db.transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await (db.update(db.categories)..where(
              (c) =>
                  c.id.equals(idsInOrder[i]) &
                  (c.position.isNull() | c.position.equals(i).not()),
            ))
            .write(
              CategoriesCompanion(
                position: Value(i),
                updatedAt: Value(now),
                dirty: const Value(true),
              ),
            );
      }
    });
  }

  /// Soft delete: `archived = true` + tombstone, atomically.
  Future<void> archive(String id) async {
    final now = currentMs;
    await db.transaction(() async {
      await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('categories', id);
    });
  }
}
