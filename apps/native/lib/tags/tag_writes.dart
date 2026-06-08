import 'package:drift/drift.dart';

import '../database.dart';
import '../utils/random_ids.dart';

class LocalTagDraft {
  const LocalTagDraft({this.id, required this.name, this.colorHex});

  final String? id;
  final String name;
  final String? colorHex;
}

String _normalizeName(String value) => value.trim().toLowerCase();

Future<Tag> createLocalTag(
  AppDatabase db, {
  required String name,
  String? colorHex,
  String? description,
  String? parentId,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Tag name is required');
  }

  final normalized = _normalizeName(trimmed);
  final existing = await (db.select(
    db.tags,
  )..where((t) => t.archived.equals(false))).get();
  for (final tag in existing) {
    if (_normalizeName(tag.name) == normalized) {
      throw ArgumentError('Tag with that name already exists');
    }
  }

  final id = newUuid();
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  await db
      .into(db.tags)
      .insert(
        TagsCompanion.insert(
          id: id,
          name: trimmed,
          description: Value(description),
          parentId: Value(parentId),
          color: Value(colorHex),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
        ),
      );

  final created = await (db.select(
    db.tags,
  )..where((t) => t.id.equals(id))).getSingle();
  return created;
}

Future<Tag> ensureLocalTag(AppDatabase db, LocalTagDraft draft) async {
  if (draft.id != null) {
    final byId =
        await (db.select(db.tags)
              ..where((t) => t.id.equals(draft.id!) & t.archived.equals(false)))
            .getSingleOrNull();
    if (byId != null) return byId;
  }

  final normalized = _normalizeName(draft.name);
  final existing = await (db.select(
    db.tags,
  )..where((t) => t.archived.equals(false))).get();
  for (final tag in existing) {
    if (_normalizeName(tag.name) == normalized) return tag;
  }

  return createLocalTag(db, name: draft.name, colorHex: draft.colorHex);
}
