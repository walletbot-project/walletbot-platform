import 'package:app/components/color_utils.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TagsView extends StatelessWidget {
  const TagsView({super.key});

  @override
  Widget build(BuildContext context) {
    final tags = context.read<AppRepositories>().tags;

    return StreamBuilder<List<TagWithCount>>(
      stream: tags.watchWithCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('No tags yet.'));
        }

        final tree = _buildTagTree(data);

        return ListView.builder(
          itemCount: tree.length,
          itemBuilder: (context, index) {
            final entry = tree[index];
            final tag = entry.row.tag;
            final color = colorFromHex(tag.color);

            return Padding(
              padding: EdgeInsets.only(left: entry.depth * 20.0),
              child: ListTile(
                onLongPress: () => _editTagDialog(
                  context,
                  tags,
                  tag,
                  data.map((t) => t.tag).toList(),
                ),
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const CircleAvatar(backgroundColor: Colors.white),
                    backgroundColor: color,
                    label: Text(tag.name),
                  ),
                ),
                trailing: Text('${entry.row.transactionCount}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _TagTreeEntry {
  _TagTreeEntry({required this.row, required this.depth});

  final TagWithCount row;
  final int depth;
}

List<_TagTreeEntry> _buildTagTree(List<TagWithCount> rows) {
  final rowsById = {for (final r in rows) r.tag.id: r};
  final childrenByParent = <String, List<TagWithCount>>{};
  final roots = <TagWithCount>[];

  for (final row in rows) {
    final parentId = row.tag.parentId;
    if (parentId != null && rowsById.containsKey(parentId)) {
      childrenByParent.putIfAbsent(parentId, () => []).add(row);
    } else {
      roots.add(row);
    }
  }

  final result = <_TagTreeEntry>[];
  void visit(TagWithCount row, int depth) {
    result.add(_TagTreeEntry(row: row, depth: depth));
    final children = childrenByParent[row.tag.id] ?? const [];
    for (final child in children) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return result;
}

Future<void> showAddTagDialog(BuildContext context, TagRepository tags) async {
  final parentCandidates = await tags.listActive();
  if (!context.mounted) return;
  await showDialog<_TagDialogAction>(
    context: context,
    builder: (context) =>
        _TagDialog(tags: tags, parentCandidates: parentCandidates),
  );
}

Future<void> _editTagDialog(
  BuildContext context,
  TagRepository tags,
  Tag tag,
  List<Tag> allActive,
) async {
  final descendants = descendantIdsOf(allActive, tag.id);
  final parentCandidates = allActive
      .where((t) => t.id != tag.id && !descendants.contains(t.id))
      .toList();

  final action = await showDialog<_TagDialogAction>(
    context: context,
    builder: (context) =>
        _TagDialog(tags: tags, parentCandidates: parentCandidates, tag: tag),
  );

  if (action == _TagDialogAction.delete) {
    if (!context.mounted) return;
    final children = allActive.where((t) => t.parentId == tag.id).toList();
    await _confirmAndDeleteTag(context, tags, tag, children);
  }
}

enum _TagDialogAction { saved, delete }

// Owns the name controller so it lives exactly as long as the dialog widget
// and is disposed from State.dispose(), per the Flutter docs for
// TextEditingController.
class _TagDialog extends StatefulWidget {
  const _TagDialog({
    required this.tags,
    required this.parentCandidates,
    this.tag,
  });

  final TagRepository tags;
  final List<Tag> parentCandidates;
  final Tag? tag;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final TextEditingController _nameController;
  late Color _selectedColor;
  late bool _isSubtag;
  String? _parentId;

  bool get _isEditing => widget.tag != null;

  @override
  void initState() {
    super.initState();
    final tag = widget.tag;
    _nameController = TextEditingController(text: tag?.name ?? '');
    _selectedColor = tag != null ? colorFromHex(tag.color) : tagDefaultColor;
    _isSubtag = tag?.parentId != null;
    _parentId = tag?.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_isSubtag && _parentId == null) return;
    final navigator = Navigator.of(context);
    final tag = widget.tag;
    if (tag != null) {
      await widget.tags.update(
        tag.id,
        name: Value(name),
        color: Value(colorToHex(_selectedColor)),
        parentId: Value(_isSubtag ? _parentId : null),
      );
    } else {
      await widget.tags.create(
        name: name,
        color: colorToHex(_selectedColor),
        parentId: _isSubtag ? _parentId : null,
      );
    }
    navigator.pop(_TagDialogAction.saved);
  }

  @override
  Widget build(BuildContext context) {
    final parentCandidates = widget.parentCandidates;

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Tag' : 'New Tag'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            _ColorPicker(
              selected: _selectedColor,
              onChanged: (c) => setState(() => _selectedColor = c),
            ),
            if (parentCandidates.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Checkbox(
                    value: _isSubtag,
                    onChanged: (v) => setState(() {
                      _isSubtag = v ?? false;
                      if (!_isSubtag) _parentId = null;
                    }),
                  ),
                  const Text('Create sub-tag'),
                ],
              ),
            ],
            if (_isSubtag && parentCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Parent tag', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _parentId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Select parent tag'),
                items: parentCandidates
                    .map(
                      (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _parentId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: () => Navigator.pop(context, _TagDialogAction.delete),
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

Future<void> _confirmAndDeleteTag(
  BuildContext context,
  TagRepository tags,
  Tag tag,
  List<Tag> children,
) async {
  if (children.isEmpty) {
    await tags.archive(tag.id, mode: TagArchiveMode.reparentChildren);
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
            onPressed: () => Navigator.pop(context, _CascadeChoice.cascade),
            child: const Text('Delete all'),
          ),
        ],
      );
    },
  );

  if (result == null || result == _CascadeChoice.cancel) return;
  await tags.archive(
    tag.id,
    mode: result == _CascadeChoice.cascade
        ? TagArchiveMode.cascade
        : TagArchiveMode.reparentChildren,
  );
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
