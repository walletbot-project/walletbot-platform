import 'package:app/database.dart';
import 'package:app/screens/components/color_utils.dart';
import 'package:app/screens/components/insight_count_models.dart';
import 'package:app/screens/components/insights_section_header.dart';
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
        InsightsSectionHeader(onAddPressed: () => _addTagDialog(context, db)),
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

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 8, runSpacing: 8, children: data.map((tag) => TagCountChip(tag: tag)).toList()),
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
               tg.is_archived, tg.created_at, tg.updated_at, tg.dirty,
               COUNT(tt.id) AS transaction_count
        FROM tags tg
        LEFT JOIN transaction_tags tt ON tt.tag_id = tg.id
        WHERE tg.is_archived = 0
        GROUP BY tg.id, tg.name, tg.description, tg.parent_id, tg.color,
                 tg.is_archived, tg.created_at, tg.updated_at, tg.dirty
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

  Future<void> _addTagDialog(BuildContext context, AppDatabase db) async {
    final nameController = TextEditingController();
    Color selectedColor = tagDefaultColor;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Tag'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                Text('Color', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: tagColorOptions.map((color) {
                    final isSelected = color == selectedColor;

                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 2),
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
                    await db
                        .into(db.tags)
                        .insert(
                          TagsCompanion.insert(
                            id: DateTime.now().microsecondsSinceEpoch.toString(),
                            name: name,
                            color: Value(colorToHex(selectedColor)),
                            createdAt: now,
                            updatedAt: now,
                          ),
                        );
                  }

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
}

class TagCountChip extends StatelessWidget {
  const TagCountChip({super.key, required this.tag});

  final TagWithCount tag;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(tag.tag.color);

    return ActionChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text('${tag.tag.name} (${tag.transactionCount})'),
      onPressed: () {},
    );
  }
}
