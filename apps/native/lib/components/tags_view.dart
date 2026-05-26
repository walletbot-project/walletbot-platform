import 'package:app/database.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/insight_count_models.dart';
import 'package:app/components/insights_section_header.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TagsView extends StatelessWidget {
  const TagsView({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Column(
      children: [
        InsightsSectionHeader(
          onAddPressed: () => _addTagDialog(context, db),
        ),
        Expanded(
          child: StreamBuilder<List<TagWithCount>>(
            stream: _watchTagsWithCounts(db),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data ?? [];
              if (data.isEmpty) {
                return const Center(child: Text('No tags yet.'));
              }

              final tagsById = {for (final t in data) t.tag.id: t.tag};

              return ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final tag = data[index];
                  final color = colorFromHex(tag.tag.color);
                  final parent = tag.tag.parentId != null
                      ? tagsById[tag.tag.parentId]
                      : null;

                  return ListTile(
                    onLongPress: () => _editTagDialog(
                      context,
                      db,
                      tag.tag,
                      data.map((t) => t.tag).toList(),
                    ),
                    title: Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: const CircleAvatar(
                          backgroundColor: Colors.white,
                        ),
                        backgroundColor: color,
                        label: Text(tag.tag.name),
                      ),
                    ),
                    subtitle: parent != null
                        ? Text('sub-tag of ${parent.name}')
                        : null,
                    trailing: Text('${tag.transactionCount}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<List<TagWithCount>> _watchTagsWithCounts(AppDatabase db) {
    final query = db.customSelect(
      '''
        SELECT tg.id, tg.name, tg.description, tg.parent_id, tg.color,
               tg.archived, tg.created_at, tg.updated_at, tg.dirty,
               COUNT(tt.id) AS transaction_count
        FROM tags tg
        LEFT JOIN transaction_tags tt ON tt.tag_id = tg.id
        WHERE tg.archived = 0
        GROUP BY tg.id, tg.name, tg.description, tg.parent_id, tg.color,
                 tg.archived, tg.created_at, tg.updated_at, tg.dirty
        ORDER BY tg.name COLLATE NOCASE
      ''',
      readsFrom: {db.tags, db.transactionTags},
    );

    return query.watch().map((rows) {
      return rows.map((row) {
        return TagWithCount(
          tag: Tag(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            description: row.readNullable<String>('description'),
            parentId: row.readNullable<String>('parent_id'),
            color: row.readNullable<String>('color'),
            archived: row.read<bool>('archived'),
            createdAt: row.read<BigInt>('created_at'),
            updatedAt: row.read<BigInt>('updated_at'),
            dirty: row.read<bool>('dirty'),
          ),
          transactionCount: row.read<int>('transaction_count'),
        );
      }).toList();
    });
  }

  Future<List<Tag>> _loadActiveTags(AppDatabase db) async {
    return (db.select(db.tags)..where((t) => t.archived.equals(false))).get();
  }

  List<Tag> _ancestorChain(List<Tag> all, String? startParentId) {
    final byId = {for (final t in all) t.id: t};
    final chain = <Tag>[];
    final seen = <String>{};
    var cursor = startParentId;
    while (cursor != null) {
      if (seen.contains(cursor)) break;
      seen.add(cursor);
      final next = byId[cursor];
      if (next == null) break;
      chain.add(next);
      cursor = next.parentId;
    }
    return chain;
  }

  Set<String> _descendantIds(List<Tag> all, String rootId) {
    final result = <String>{};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      for (final t in all) {
        if (t.parentId == id && !result.contains(t.id)) {
          result.add(t.id);
          queue.add(t.id);
        }
      }
    }
    return result;
  }

  Future<void> _addTagDialog(BuildContext context, AppDatabase db) async {
    final existing = await _loadActiveTags(db);
    if (!context.mounted) return;
    final parentCandidates = existing.toList();
    final nameController = TextEditingController();
    Color selectedColor = tagDefaultColor;
    bool isSubtag = false;
    String? parentId;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Tag'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Color',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  _ColorPicker(
                    selected: selectedColor,
                    onChanged: (c) => setState(() => selectedColor = c),
                  ),
                  if (parentCandidates.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Checkbox(
                          value: isSubtag,
                          onChanged: (v) => setState(() {
                            isSubtag = v ?? false;
                            if (!isSubtag) parentId = null;
                          }),
                        ),
                        const Text('Create sub-tag'),
                      ],
                    ),
                  ],
                  if (isSubtag && parentCandidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Parent tag',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: parentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select parent tag'),
                      items: parentCandidates
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => parentId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  if (isSubtag && parentId == null) return;
                  await _createTag(
                    db,
                    name: name,
                    color: selectedColor,
                    parentId: isSubtag ? parentId : null,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editTagDialog(
    BuildContext context,
    AppDatabase db,
    Tag tag,
    List<Tag> allActive,
  ) async {
    final descendants = _descendantIds(allActive, tag.id);
    final parentCandidates = allActive
        .where((t) => t.id != tag.id && !descendants.contains(t.id))
        .toList();

    final nameController = TextEditingController(text: tag.name);
    Color selectedColor = colorFromHex(tag.color);
    bool isSubtag = tag.parentId != null;
    String? parentId = tag.parentId;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Tag'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Color',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  _ColorPicker(
                    selected: selectedColor,
                    onChanged: (c) => setState(() => selectedColor = c),
                  ),
                  if (parentCandidates.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Checkbox(
                          value: isSubtag,
                          onChanged: (v) => setState(() {
                            isSubtag = v ?? false;
                            if (!isSubtag) parentId = null;
                          }),
                        ),
                        const Text('Create sub-tag'),
                      ],
                    ),
                  ],
                  if (isSubtag && parentCandidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Parent tag',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: parentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select parent tag'),
                      items: parentCandidates
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => parentId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final children = allActive
                      .where((t) => t.parentId == tag.id)
                      .toList();
                  await _confirmAndDeleteTag(context, db, tag, children);
                },
                child: const Text('Delete'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  if (isSubtag && parentId == null) return;
                  await _updateTag(
                    db,
                    tag: tag,
                    name: name,
                    color: selectedColor,
                    newParentId: isSubtag ? parentId : null,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createTag(
    AppDatabase db, {
    required String name,
    required Color color,
    required String? parentId,
  }) async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            color: Value(colorToHex(color)),
            parentId: Value(parentId),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
  }

  Future<void> _updateTag(
    AppDatabase db, {
    required Tag tag,
    required String name,
    required Color color,
    required String? newParentId,
  }) async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final previousParentId = tag.parentId;

    await db.transaction(() async {
      await (db.update(db.tags)..where((t) => t.id.equals(tag.id))).write(
        TagsCompanion(
          name: Value(name),
          color: Value(colorToHex(color)),
          parentId: Value(newParentId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );

      if (newParentId != null && newParentId != previousParentId) {
        // Every transaction tagged with this tag (or any of its descendants)
        // must also carry every ancestor in the new chain.
        final allActive = await _loadActiveTags(db);
        final ancestors = _ancestorChain(allActive, newParentId);
        final descendants = _descendantIds(allActive, tag.id);
        final affectedTagIds = <String>{tag.id, ...descendants};

        final transactionIds = <String>{};
        for (final tagId in affectedTagIds) {
          final joins = await (db.select(
            db.transactionTags,
          )..where((tt) => tt.tagId.equals(tagId))).get();
          for (final j in joins) {
            transactionIds.add(j.transactionId);
          }
        }

        for (final txId in transactionIds) {
          for (final ancestor in ancestors) {
            final existing =
                await (db.select(db.transactionTags)
                      ..where((tt) => tt.transactionId.equals(txId))
                      ..where((tt) => tt.tagId.equals(ancestor.id)))
                    .getSingleOrNull();
            if (existing != null) continue;
            await db
                .into(db.transactionTags)
                .insert(
                  TransactionTagsCompanion.insert(
                    id: '${DateTime.now().microsecondsSinceEpoch}_${txId}_${ancestor.id}',
                    transactionId: txId,
                    tagId: ancestor.id,
                    createdAt: now,
                    updatedAt: now,
                    dirty: const Value(true),
                  ),
                );
          }
        }
      }
    });
  }

  Future<void> _confirmAndDeleteTag(
    BuildContext context,
    AppDatabase db,
    Tag tag,
    List<Tag> children,
  ) async {
    if (children.isEmpty) {
      await _deleteTag(db, tag.id, cascade: false);
      return;
    }

    final result = await showDialog<_CascadeChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete tag with sub-tags'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tag.name} has ${children.length} sub-tag${children.length == 1 ? '' : 's'}. Do you want to delete the sub-tags too?',
              ),
              const SizedBox(height: 8),
              ...children.map((c) => Text('• ${c.name}')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _CascadeChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _CascadeChoice.keep),
              child: const Text('Keep sub-tags'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _CascadeChoice.cascade),
              child: const Text('Delete all'),
            ),
          ],
        );
      },
    );

    if (result == null || result == _CascadeChoice.cancel) return;
    await _deleteTag(db, tag.id, cascade: result == _CascadeChoice.cascade);
  }

  Future<void> _deleteTag(
    AppDatabase db,
    String id, {
    required bool cascade,
  }) async {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    await db.transaction(() async {
      if (cascade) {
        final allActive = await _loadActiveTags(db);
        final descendants = _descendantIds(allActive, id);
        for (final descendantId in descendants) {
          await (db.update(db.tags)..where((t) => t.id.equals(descendantId)))
              .write(
                TagsCompanion(
                  archived: const Value(true),
                  updatedAt: Value(now),
                  dirty: const Value(true),
                ),
              );
        }
      } else {
        final directChildren = await (db.select(db.tags)
              ..where((t) => t.parentId.equals(id))
              ..where((t) => t.archived.equals(false)))
            .get();
        for (final child in directChildren) {
          await (db.update(db.tags)..where((t) => t.id.equals(child.id)))
              .write(
                TagsCompanion(
                  parentId: const Value(null),
                  updatedAt: Value(now),
                  dirty: const Value(true),
                ),
              );
        }
      }

      await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
    });
  }
}

enum _CascadeChoice { cancel, keep, cascade }

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final Color selected;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: tagColorOptions.map((color) {
        final isSelected = color == selected;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: isSelected ? const Icon(Icons.check, size: 18) : null,
          ),
        );
      }).toList(),
    );
  }
}
