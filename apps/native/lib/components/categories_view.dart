import 'package:app/components/category_icons.dart';
import 'package:app/components/category_list_tile.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/icon_picker.dart';
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

class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key, required this.onSelect});

  /// Called when a category row is tapped. The Insights screen owns the
  /// selection and presents the detail — the shared split pane on expanded
  /// windows, a modal bottom sheet everywhere else — so the pane sits
  /// outside the sliding tab pages.
  final void Function(CategoryWithCount entry) onSelect;

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

/// The categories list — one page of the Insights tab view. Pure list: all
/// detail/creation presentation lives in the Insights screen.
class _CategoriesViewState extends State<CategoriesView>
    with AutomaticKeepAliveClientMixin {
  /// Keeps the list (its scroll position) alive when the Insights tabs swipe
  /// this view out of the TabBarView.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categories = context.read<AppRepositories>().categories;

    return StreamBuilder<List<CategoryWithCount>>(
      stream: categories.watchWithCounts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CategoriesMessage(
            icon: Icons.error_outline_rounded,
            title: context.l10n.categoriesLoadFailed,
            detail: snapshot.error.toString(),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <CategoryWithCount>[];
        if (data.isEmpty) {
          return _CategoriesMessage(
            icon: Icons.category_outlined,
            title: context.l10n.noCategoriesTitle,
            detail: context.l10n.noCategoriesBody,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: data.length,
          separatorBuilder: (_, _) => const SizedBox(height: kGroupSpacing),
          itemBuilder: (context, index) {
            final entry = data[index];
            final category = entry.category;
            return CategoryListTile(
              name: category.name,
              icon: categoryIconFromName(category.icon),
              color: colorFromHex(
                category.color,
                fallback: categoryDefaultColor,
              ),
              usageCount: entry.transactionCount,
              borderRadius: groupedRadius(index, data.length),
              onTap: () => widget.onSelect(entry),
            );
          },
        );
      },
    );
  }
}

class _CategoriesMessage extends StatelessWidget {
  const _CategoriesMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colors.outline),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Draggable, scrollable modal sheet showing a category's details. Edits to the
/// name, color and icon are committed on leaving edit mode.
class CategoryDetailsSheet extends StatefulWidget {
  const CategoryDetailsSheet({
    super.key,
    required this.category,
    required this.repos,
    required this.nav,
    this.onClose,
  });

  final Category category;
  final AppRepositories repos;
  final AppNavigation nav;

  /// Embedded (split pane) mode: when set, the sheet never pops a route —
  /// exits report here instead, the drag-to-size scaffolding is dropped, and
  /// an explicit close button is shown.
  final VoidCallback? onClose;

  @override
  State<CategoryDetailsSheet> createState() => _CategoryDetailsSheetState();
}

class _CategoryDetailsSheetState extends State<CategoryDetailsSheet> {
  late Color _color = colorFromHex(
    widget.category.color,
    fallback: categoryDefaultColor,
  );
  late IconData _icon = categoryIconFromName(widget.category.icon);
  late final TextEditingController _nameController = TextEditingController(
    text: widget.category.name,
  );

  bool _editing = false;
  bool _saving = false;

  String get _categoryId => widget.category.id;

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

  Future<void> _editIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: categoryIconOptions,
      accent: _color,
    );
    if (picked != null) setState(() => _icon = picked);
  }

  /// Toggles edit mode. Entering reveals the editors; leaving validates and
  /// persists name/color/icon.
  Future<void> _toggleEditing() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.repos.categories.update(
        _categoryId,
        name: Value(name),
        color: Value(colorToHex(_color)),
        icon: Value(categoryIconName(_icon)),
      );
      if (!mounted) return;
      setState(() => _editing = false);
    } catch (e, st) {
      debugPrint('Error updating category: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.categorySaveFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(context.l10n.deleteCategory),
          content: Text(
            context.l10n.deleteCategoryConfirmation(
              _nameController.text.trim(),
            ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repos.categories.archive(_categoryId);
      if (!mounted) return;
      _close(); // close the details sheet
    } catch (e, st) {
      debugPrint('Error archiving category: $e\n$st');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.deleteCategoryFailed)),
        );
      }
    }
  }

  void _openAllTransactions() {
    _close(); // close the sheet before switching tabs
    widget.nav.openActivityForCategory(_categoryId);
  }

  /// Exits the sheet: reports to [CategoryDetailsSheet.onClose] when embedded
  /// in the split pane, pops the modal route otherwise.
  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Editing state lives in this State object, above the branch below, so
    // it survives when the presentation morphs between sheet and pane.
    if (widget.onClose != null) {
      // Panel presentation (split pane or dialog): a standard app bar, so the
      // pane's content starts at the same height as the list column's beside
      // it, and the close button matches every other panel in the app.
      // Embedded there is no route to pop, so no back button appears on its
      // own — offer an explicit close instead.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(context.l10n.categoryDetails),
        ),
        body: _buildSheetBody(context, null),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: _buildSheetBody,
    );
  }

  Widget _buildSheetBody(
    BuildContext context,
    ScrollController? scrollController,
  ) {
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
  }

  /// The category name: an inline text field while editing, plain text otherwise.
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

  /// Identity + usage as one cohesive M3 Expressive containment group: a
  /// color-washed identity hero (icon, name, optional description, color swatch)
  /// joined by the 2dp seam to the usage hero (movement count).
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final description = widget.category.description;

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
                // Expressive rounded-square icon tile — tappable only while
                // editing, to change the icon.
                InkWell(
                  onTap: _editing ? _editIcon : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 30, color: _color),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildName(textTheme),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Discrete color swatch — only shown while editing; tap to
                // change the category color.
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
        // makes the card fill the full width (a bare Column would shrink to
        // its text).
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

  /// The amount spent in this category during the current month. Sums expense
  /// rows by currency; when the category mixes currencies the dominant one is
  /// shown big with a small note for the rest.
  Widget _buildMonthlySpend(TextTheme textTheme) {
    final window = const TransactionFilter(
      datePreset: DatePreset.thisMonth,
    ).resolveDateWindow()!;

    return StreamBuilder<Map<String, BigInt>>(
      stream: widget.repos.categories.watchSpendByCurrency(
        _categoryId,
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

        // Pick the currency with the largest total to headline the figure.
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

  /// Category actions as Material 3 Expressive buttons: edit and a destructive
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
  /// Activity tab filtered to this category.
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

  /// The five most recent movements in this category, rendered with the shared
  /// [TransactionRow]. Handles loading, error and empty states.
  Widget _buildTransactions(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: widget.repos.transactions.watch(
        TransactionFilter(categoryIds: {_categoryId}),
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
                title: context.l10n.transactionName(txs[i].name, txs[i].type),
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
