import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/shared/money.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:m3e_buttons/m3e_buttons.dart';
import 'package:provider/provider.dart';

class TagsView extends StatelessWidget {
  const TagsView({super.key});

  /// Opens the tag details as a draggable, scrollable modal sheet. The sheet is
  /// a pushed route below the account-scoped providers, so the data layer and
  /// navigation controller are captured here and handed down.
  void _openTagSheet(BuildContext context, Tag tag) {
    final repos = context.read<AppRepositories>();
    final nav = context.read<AppNavigation>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TagDetailsSheet(tag: tag, repos: repos, nav: nav),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = context.read<AppRepositories>().tags;

    return StreamBuilder<List<TagWithCount>>(
      stream: tags.watchWithCounts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(context.l10n.tagsLoadFailed));
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <TagWithCount>[];
        if (data.isEmpty) {
          return Center(child: Text(context.l10n.noTagsYet));
        }

        final tree = _buildTagTree(data);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          itemCount: tree.length,
          itemBuilder: (context, index) {
            final entry = tree[index];
            final tag = entry.row.tag;
            final color = colorFromHex(tag.color);

            // The chip stays as the tag's representation; tapping it opens the
            // details sheet. Sub-tags keep their indentation.
            return Padding(
              padding: EdgeInsets.only(
                left: entry.depth * 20.0,
                top: 4,
                bottom: 4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const CircleAvatar(backgroundColor: Colors.white),
                  backgroundColor: color,
                  label: Text(tag.name),
                  onPressed: () => _openTagSheet(context, tag),
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Details sheet — mirrors the account/category sheets, minus the icon (tags
// carry a color but no icon).
// ─────────────────────────────────────────────────────────────────────────────

/// Draggable, scrollable modal sheet showing a tag's details. Edits to the name
/// and color are committed on leaving edit mode.
class TagDetailsSheet extends StatefulWidget {
  const TagDetailsSheet({
    super.key,
    required this.tag,
    required this.repos,
    required this.nav,
  });

  final Tag tag;
  final AppRepositories repos;
  final AppNavigation nav;

  @override
  State<TagDetailsSheet> createState() => _TagDetailsSheetState();
}

class _TagDetailsSheetState extends State<TagDetailsSheet> {
  late Color _color = colorFromHex(widget.tag.color);
  late final TextEditingController _nameController = TextEditingController(
    text: widget.tag.name,
  );

  bool _editing = false;
  bool _saving = false;

  String get _tagId => widget.tag.id;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editColor() async {
    final picked = await showColorPickerDialog(
      context,
      selected: _color,
      options: colorOptions,
    );
    if (picked != null) setState(() => _color = picked);
  }

  /// Toggles edit mode. Entering reveals the editors; leaving validates and
  /// persists name/color.
  Future<void> _toggleEditing() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.repos.tags.update(
        _tagId,
        name: Value(name),
        color: Value(colorToHex(_color)),
      );
      if (!mounted) return;
      setState(() => _editing = false);
    } catch (e, st) {
      debugPrint('Error updating tag: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.tagSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final all = await widget.repos.tags.listActive();
    if (!mounted) return;
    final children = all.where((t) => t.parentId == _tagId).toList();

    final TagArchiveMode mode;
    if (children.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Text(context.l10n.deleteTag),
            content: Text(
              context.l10n.deleteTagConfirmation(_nameController.text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: colors.error),
                child: Text(context.l10n.delete),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return;
      mode = TagArchiveMode.reparentChildren;
    } else {
      // The tag has sub-tags: confirm AND ask what happens to them.
      final choice = await showDialog<_CascadeChoice>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Text(context.l10n.deleteTagWithChildren),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.deleteTagWithChildrenPrompt(
                    _nameController.text.trim(),
                    children.length,
                  ),
                ),
                const SizedBox(height: 8),
                ...children.map((c) => Text('• ${c.name}')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_CascadeChoice.cancel),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_CascadeChoice.keep),
                child: Text(context.l10n.keepSubtags),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_CascadeChoice.cascade),
                style: TextButton.styleFrom(foregroundColor: colors.error),
                child: Text(context.l10n.deleteEverything),
              ),
            ],
          );
        },
      );
      if (choice == null || choice == _CascadeChoice.cancel || !mounted) return;
      mode = choice == _CascadeChoice.cascade
          ? TagArchiveMode.cascade
          : TagArchiveMode.reparentChildren;
    }

    setState(() => _saving = true);
    try {
      await widget.repos.tags.archive(_tagId, mode: mode);
      if (!mounted) return;
      Navigator.of(context).pop(); // close the details sheet
    } catch (e, st) {
      debugPrint('Error archiving tag: $e\n$st');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openAllTransactions() {
    Navigator.of(context).pop(); // close the sheet before switching tabs
    widget.nav.openActivityForTag(_tagId);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _buildIdentityGroup(context),
            const SizedBox(height: 12),
            _buildActions(context),
            const SizedBox(height: 28),
            _buildTransactionsHeader(context),
            const SizedBox(height: 8),
            _buildTransactions(context),
          ],
        );
      },
    );
  }

  /// The tag name: an inline text field while editing, plain text otherwise.
  Widget _buildName(TextTheme textTheme) {
    final style = textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
    if (_editing) {
      return TextField(
        controller: _nameController,
        style: style,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          isDense: true,
          labelText: context.l10n.name,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );
    }
    return Text(
      _nameController.text,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Identity + spend as one cohesive M3 Expressive containment group. Tags
  /// have no icon, so the identity hero is just the color-washed name (plus the
  /// editable color swatch), joined by the 2dp seam to the spend hero.
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Material(
          color: _color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupOuterRadius),
            bottom: Radius.circular(kGroupInnerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(child: _buildName(textTheme)),
                // Discrete color swatch — only shown while editing; tap to
                // change the tag color.
                if (_editing) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _editColor,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: kGroupSpacing),
        // Spend hero — total spent this month. A Row with an Expanded child
        // makes the card fill the full width.
        GroupedCard(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupInnerRadius),
            bottom: Radius.circular(kGroupOuterRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.spentThisMonth,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildMonthlySpend(textTheme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The amount spent on this tag during the current month. Sums expense rows
  /// by currency; when the tag mixes currencies the dominant one is shown big
  /// with a small note for the rest.
  Widget _buildMonthlySpend(TextTheme textTheme) {
    final window = const TransactionFilter(
      datePreset: DatePreset.thisMonth,
    ).resolveDateWindow()!;

    return StreamBuilder<Map<String, BigInt>>(
      stream: widget.repos.tags.watchSpendByCurrency(
        _tagId,
        fromMs: window.fromMs!,
        toExclusiveMs: window.toExclusiveMs!,
      ),
      builder: (context, snapshot) {
        final spend = snapshot.data ?? const <String, BigInt>{};
        final bigStyle = textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
        );

        if (spend.isEmpty) {
          return Text(
            context.l10n.noSpendingThisMonth,
            style: textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }

        final entries = spend.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top = entries.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatMoney(
                top.value.toInt(),
                top.key,
                locale: context.localeName,
              ),
              style: bigStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (entries.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.l10n.otherCurrencies(entries.length - 1),
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Tag actions as Material 3 Expressive buttons: edit and a destructive
  /// delete.
  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: M3EFilledButton.tonalIcon(
            onPressed: _saving ? null : _toggleEditing,
            size: M3EButtonSize.md,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
            label: Text(_editing ? context.l10n.done : context.l10n.edit),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: _saving ? null : _confirmDelete,
          size: M3EButtonSize.md,
          tooltip: context.l10n.delete,
          semanticLabel: context.l10n.delete,
          decoration: M3EButtonDecoration.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          child: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// "Last movements" section header with a "view all" action that opens the
  /// Activity tab filtered to this tag.
  Widget _buildTransactionsHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.latestMovements,
            style: textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: _openAllTransactions,
          child: Text(context.l10n.viewAll),
        ),
      ],
    );
  }

  /// The five most recent movements carrying this tag, rendered with the shared
  /// [TransactionRow]. Handles loading, error and empty states.
  Widget _buildTransactions(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: widget.repos.transactions.watch(
        TransactionFilter(tagIds: {_tagId}),
        limit: 5,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _hintText(context, context.l10n.movementsLoadFailed);
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final txs = snapshot.data ?? const <Transaction>[];
        if (txs.isEmpty) {
          return _hintText(context, context.l10n.noMovementsYet);
        }
        return Column(
          children: [
            for (var i = 0; i < txs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              TransactionRow(
                title: context.l10n.transactionName(txs[i].name),
                amountCents: _signedAmountCents(txs[i]),
                dateCheck: txs[i].dateConfirmed,
                description: _shortDate(context, txs[i].date),
                currencySymbol: currencyPrefix(txs[i].currency).trim(),
                onTap: () {},
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _hintText(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Signed cents for [TransactionRow]: positive renders green, negative renders
/// in the default text color. Mirrors the activity screen's convention.
int _signedAmountCents(Transaction t) {
  final amount = t.amount.toInt();
  switch (t.type) {
    case 'expense':
      return -amount.abs();
    case 'income':
    case 'transfer':
      return amount.abs();
    default: // balance_adjustment keeps its stored sign
      return amount;
  }
}

/// Compact `day month` label, e.g. `27 may`.
String _shortDate(BuildContext context, BigInt dateMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(dateMs.toInt());
  return formatShortDate(dt, context.localeName);
}

// ─────────────────────────────────────────────────────────────────────────────
// Create dialog — reached from the Insights "+" action. Tags carry a name,
// color and optional parent (no icon).
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showAddTagDialog(BuildContext context, TagRepository tags) async {
  final parentCandidates = await tags.listActive();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _TagDialog(tags: tags, parentCandidates: parentCandidates),
  );
}

// Owns the name controller so it lives exactly as long as the dialog widget
// and is disposed from State.dispose(), per the Flutter docs for
// TextEditingController.
class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.tags, required this.parentCandidates});

  final TagRepository tags;
  final List<Tag> parentCandidates;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final TextEditingController _nameController;
  Color _selectedColor = tagDefaultColor;
  bool _isSubtag = false;
  String? _parentId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
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
    await widget.tags.create(
      name: name,
      color: colorToHex(_selectedColor),
      parentId: _isSubtag ? _parentId : null,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final parentCandidates = widget.parentCandidates;

    return AlertDialog(
      title: Text(context.l10n.newTag),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.l10n.name),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.color,
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
                  Text(context.l10n.createSubtag),
                ],
              ),
            ],
            if (_isSubtag && parentCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.parentTag,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _parentId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: Text(context.l10n.chooseParentTag),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.create)),
      ],
    );
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
      children: colorOptions.map((color) {
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
