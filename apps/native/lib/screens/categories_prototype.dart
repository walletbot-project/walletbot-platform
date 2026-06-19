import 'package:app/components/category_icons.dart';
import 'package:app/components/category_list_tile.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/components/transaction_row.dart';
import 'package:app/screens/accounts_prototype.dart';
import 'package:app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:m3e_buttons/m3e_buttons.dart';

/// Mock category model shaped after the real backend fields:
/// name, optional description, isArchived. Categories have NO `color` and NO
/// hierarchy in the backend schema, so the accent color/icon below are
/// prototype-only visuals (chosen to match the accounts style). The movement
/// count is a prototype-only stat; categories carry no balance.
class Category {
  const Category({
    required this.name,
    required this.icon,
    required this.color,
    this.description,
    required this.usageCount,
    this.currency = 'USD',
    this.transactions = _sampleCategoryTransactions,
  });

  final String name;
  final IconData icon; // prototype-only visual
  final Color color; // prototype-only visual accent
  final String? description; // backend `description`
  final int usageCount; // # of movements in this category (prototype stat)
  final String currency; // ISO code for movement amounts
  final List<Transaction> transactions; // most-recent first
}

/// Shared mock movements reused across categories for the prototype.
const List<Transaction> _sampleCategoryTransactions = [
  Transaction(
    title: 'Supermercado',
    date: '24 may',
    amountCents: -8450,
    icon: Icons.shopping_cart_rounded,
  ),
  Transaction(
    title: 'Farmacia',
    date: '23 may',
    amountCents: -3120,
    icon: Icons.local_pharmacy_rounded,
  ),
  Transaction(
    title: 'Servicios',
    date: '21 may',
    amountCents: -15400,
    icon: Icons.receipt_long_rounded,
  ),
  Transaction(
    title: 'Suscripción',
    date: '20 may',
    amountCents: -999,
    icon: Icons.subscriptions_rounded,
  ),
];

const List<Category> _mockCategories = [
  Category(
    name: 'Gastos fijos',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF3B82F6),
    description: 'Alquiler, servicios y suscripciones',
    usageCount: 24,
  ),
  Category(
    name: 'Variables',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFFF59E0B),
    description: 'Compras del día a día',
    usageCount: 58,
  ),
  Category(
    name: 'Ahorro e inversión',
    icon: Icons.savings_rounded,
    color: Color(0xFF14B8A6),
    description: 'Aportes a metas y fondos',
    usageCount: 9,
  ),
  Category(
    name: 'Salud',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEF4444),
    usageCount: 12,
  ),
  Category(
    name: 'Educación',
    icon: Icons.school_rounded,
    color: Color(0xFF8B5CF6),
    description: 'Cursos, libros y formación',
    usageCount: 6,
  ),
  Category(
    name: 'Sin categoría',
    icon: Icons.help_outline_rounded,
    color: Color(0xFF6B7280),
    usageCount: 17,
  ),
];

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openCategorySheet(_mockCategories[0]),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        itemCount: _mockCategories.length,
        separatorBuilder: (_, _) => const SizedBox(height: kGroupSpacing),
        itemBuilder: (context, index) {
          final category = _mockCategories[index];
          return CategoryListTile(
            name: category.name,
            icon: category.icon,
            color: category.color,
            usageCount: category.usageCount,
            borderRadius: groupedRadius(index, _mockCategories.length),
            onTap: () => _openCategorySheet(category),
          );
        },
      ),
    );
  }

  /// Opens the category details as a draggable, scrollable modal sheet.
  void _openCategorySheet(Category category) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CategoryDetailsSheet(category: category),
    );
  }
}

/// Draggable, scrollable modal sheet showing a category's details.
class CategoryDetailsSheet extends StatefulWidget {
  const CategoryDetailsSheet({super.key, required this.category});

  final Category category;

  @override
  State<CategoryDetailsSheet> createState() => _CategoryDetailsSheetState();
}

class _CategoryDetailsSheetState extends State<CategoryDetailsSheet> {
  // Locally editable values — the controls mutate these. The mock list behind
  // the sheet is const, so edits live for the sheet's lifetime.
  late Color _color = widget.category.color;
  late IconData _icon = widget.category.icon;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.category.name,
  );

  // Edit mode is toggled by the pencil action: only then do the name field and
  // color swatch appear and the icon tile become tappable.
  bool _editing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editColor() async {
    final picked = await showColorPickerDialog(context, selected: _color);
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

  /// The category name: an inline text field while editing, plain text otherwise.
  Widget _buildName(TextTheme textTheme) {
    final style = textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
    if (_editing) {
      return TextField(
        controller: _nameController,
        style: style,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Nombre',
          border: OutlineInputBorder(),
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
  /// joined by the 2dp seam to the usage hero (total + count).
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
                      if (widget.category.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.category.description!,
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
        // Usage hero — total accumulated and movement count.
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
                        'MOVIMIENTOS',
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.category.usageCount}',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  /// Category actions as Material 3 Expressive buttons: edit, delete.
  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: M3EFilledButton.tonalIcon(
            onPressed: () => setState(() => _editing = !_editing),
            size: M3EButtonSize.md,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
            label: Text(_editing ? 'Listo' : 'Editar'),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: () {},
          size: M3EButtonSize.md,
          tooltip: 'Eliminar',
          semanticLabel: 'Eliminar',
          decoration: M3EButtonDecoration.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          child: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  /// "Last movements" section header with a "view all" action.
  Widget _buildTransactionsHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text('Últimos movimientos', style: textTheme.titleMedium),
        ),
        TextButton(onPressed: () {}, child: const Text('Ver todos')),
      ],
    );
  }

  /// Recent movements, rendered with the shared [TransactionRow] used by the
  /// activity view. The date label rides along as the row's description.
  Widget _buildTransactions(BuildContext context) {
    final txs = widget.category.transactions;
    final symbol = currencyPrefix(widget.category.currency).trim();
    return Column(
      children: [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          TransactionRow(
            title: txs[i].title,
            amountCents: txs[i].amountCents,
            dateCheck: true,
            description: txs[i].date,
            currencySymbol: symbol,
            onTap: () {},
          ),
        ],
      ],
    );
  }
}
