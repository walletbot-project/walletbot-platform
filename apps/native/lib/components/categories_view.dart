import 'package:app/categories/category_writes.dart';
import 'package:app/database.dart';
import 'package:app/components/insight_count_models.dart';
import 'package:app/sync/local_writes.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return StreamBuilder<List<CategoryWithCount>>(
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

            return ListTile(
              title: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () =>
                    _editCategoryDialog(context, db, category.category),
                child: Text(category.category.name),
              ),
              trailing: Text('${category.transactionCount}'),
            );
          },
        );
      },
    );
  }
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

Future<void> showAddCategoryDialog(BuildContext context, AppDatabase db) {
  return showDialog<_CategoryDialogAction>(
    context: context,
    builder: (context) => _CategoryDialog(db: db),
  );
}

Future<void> _editCategoryDialog(
  BuildContext context,
  AppDatabase db,
  Category category,
) async {
  final action = await showDialog<_CategoryDialogAction>(
    context: context,
    builder: (context) => _CategoryDialog(db: db, category: category),
  );

  if (action == _CategoryDialogAction.delete) {
    await _deleteCategory(db, category.id);
  }
}

enum _CategoryDialogAction { saved, delete }

// Owns the name controller so it lives exactly as long as the dialog widget
// and is disposed from State.dispose(), per the Flutter docs for
// TextEditingController.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.db, this.category});

  final AppDatabase db;
  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _nameController;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final navigator = Navigator.of(context);
    if (name.isNotEmpty) {
      final category = widget.category;
      if (category != null) {
        await _updateCategory(widget.db, category.id, name);
      } else {
        await createLocalCategory(widget.db, name: name);
      }
    }
    navigator.pop(_CategoryDialogAction.saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Category' : 'New Category'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Name'),
        autofocus: true,
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _CategoryDialogAction.delete),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

Future<void> _updateCategory(AppDatabase db, String id, String name) async {
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  await (db.update(
    db.categories,
  )..where((category) => category.id.equals(id))).write(
    CategoriesCompanion(
      name: Value(name),
      updatedAt: Value(now),
      dirty: const Value(true),
    ),
  );
}

Future<void> _deleteCategory(AppDatabase db, String id) async {
  final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
  await db.transaction(() async {
    await (db.update(
      db.categories,
    )..where((category) => category.id.equals(id))).write(
      CategoriesCompanion(
        archived: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    await writeTombstone(db, 'categories', id);
  });
}
