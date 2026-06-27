import 'package:drift/drift.dart';

import '../database.dart';
import '../utils/random_ids.dart';

String _normalizeCategoryName(String value) => value.trim().toLowerCase();

Future<Category> createLocalCategory(
  AppDatabase db, {
  required String name,
}) async {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    throw ArgumentError('Category name is required');
  }

  final existing = await (db.select(
    db.categories,
  )..where((t) => t.archived.equals(false))).get();
  final normalizedName = _normalizeCategoryName(trimmedName);
  for (final category in existing) {
    if (_normalizeCategoryName(category.name) == normalizedName) {
      throw ArgumentError('Category with that name already exists');
    }
  }

  final id = newUuid();
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          name: trimmedName,
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ),
      );
  return (db.select(db.categories)..where((t) => t.id.equals(id))).getSingle();
}
