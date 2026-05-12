import 'package:app/database.dart';
import 'package:app/screens/components/insight_count_models.dart';
import 'package:app/screens/components/insights_section_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Column(
      children: [
        InsightsSectionHeader(onAddPressed: () => _addCategoryDialog(context, db)),
        Expanded(
          child: StreamBuilder<List<CategoryWithCount>>(
            stream: _watchCategoriesWithCounts(db),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data ?? [];
              if (data.isEmpty) {
                return const Center(child: Text('No categories yet.'));
              }

              return ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final category = data[index];

                  return ListTile(title: Text(category.category.name), trailing: Text('${category.transactionCount}'));
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<List<CategoryWithCount>> _watchCategoriesWithCounts(AppDatabase db) {
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

  Future<void> _addCategoryDialog(BuildContext context, AppDatabase db) async {
    final nameController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
                await db
                    .into(db.categories)
                    .insert(
                      CategoriesCompanion.insert(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        name: name,
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
      ),
    );
  }
}
