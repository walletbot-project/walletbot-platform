import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = context.read<AppRepositories>().categories;

    return StreamBuilder<List<CategoryWithCount>>(
      stream: categories.watchWithCounts(),
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
                    _editCategoryDialog(context, categories, category.category),
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

Future<void> showAddCategoryDialog(
  BuildContext context,
  CategoryRepository categories,
) {
  return showDialog<_CategoryDialogAction>(
    context: context,
    builder: (context) => _CategoryDialog(categories: categories),
  );
}

Future<void> _editCategoryDialog(
  BuildContext context,
  CategoryRepository categories,
  Category category,
) async {
  final action = await showDialog<_CategoryDialogAction>(
    context: context,
    builder: (context) =>
        _CategoryDialog(categories: categories, category: category),
  );

  if (action == _CategoryDialogAction.delete) {
    await categories.archive(category.id);
  }
}

enum _CategoryDialogAction { saved, delete }

// Owns the name controller so it lives exactly as long as the dialog widget
// and is disposed from State.dispose(), per the Flutter docs for
// TextEditingController.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.categories, this.category});

  final CategoryRepository categories;
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
        await widget.categories.update(category.id, name: Value(name));
      } else {
        await widget.categories.create(name: name);
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
