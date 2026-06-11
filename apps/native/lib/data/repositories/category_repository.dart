import 'package:drift/drift.dart';

import '../../database.dart';
import '../ids.dart';
import '../models/entity_counts.dart';
import 'repository_base.dart';

/// Reads and writes for transaction categories.
class CategoryRepository extends RepositoryBase {
  CategoryRepository(super.db);

  /// Active categories, unsorted (sort at the call site if needed).
  Stream<List<Category>> watchActive() =>
      (db.select(db.categories)..where((c) => c.archived.equals(false)))
          .watch();

  /// One-shot list, active-only by default.
  Future<List<Category>> listAll({bool includeArchived = false}) {
    final query = db.select(db.categories);
    if (!includeArchived) {
      query.where((c) => c.archived.equals(false));
    }
    return query.get();
  }

  /// Alias of [listAll] with the default scope, for readable call sites.
  Future<List<Category>> listActive() => listAll();

  /// Exact-id lookup; finds archived categories too. Null when missing.
  Future<Category?> getById(String id) => (db.select(db.categories)
        ..where((c) => c.id.equals(id)))
      .getSingleOrNull();

  /// Active categories with their transaction counts, name-ordered. The
  /// `readsFrom` set is what keeps the count live when sync merges land —
  /// keep it in lockstep with the SQL.
  Stream<List<CategoryWithCount>> watchWithCounts() {
    final query = db.customSelect(
      '''
        SELECT c.id, c.name, c.description, c.is_archived, c.created_at,
               c.updated_at, c.dirty, COUNT(t.id) AS transaction_count
        FROM categories c
        LEFT JOIN transactions t ON t.category_id = c.id
        WHERE c.is_archived = 0
        GROUP BY c.id, c.name, c.description, c.is_archived, c.created_at,
                 c.updated_at, c.dirty
        ORDER BY c.name COLLATE NOCASE
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

  /// Creates a category and returns its new id.
  Future<String> create({required String name, String? description}) async {
    final id = newUuid();
    final now = currentMs;
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            description: Value(description),
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
  }) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: name,
        description: description,
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
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
