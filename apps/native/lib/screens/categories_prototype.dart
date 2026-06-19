import 'package:app/components/category_list_tile.dart';
import 'package:app/components/grouped_card.dart';
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
class CategoryDetailsSheet extends StatelessWidget {
  const CategoryDetailsSheet({super.key, required this.category});

  final Category category;

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

  /// Identity + usage as one cohesive M3 Expressive containment group: a
  /// color-washed identity hero (icon, name, optional description) joined by
  /// the 2dp seam to the usage hero (total + count). Categories have no color
  /// attribute, so there is no trailing color swatch.
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Material(
          color: category.color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kGroupOuterRadius),
            bottom: Radius.circular(kGroupInnerRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Icon(category.icon, size: 30, color: category.color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (category.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          category.description!,
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
                        '${category.usageCount}',
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

  /// Category actions as Material 3 Expressive buttons: edit, archive, delete.
  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: M3EFilledButton.tonalIcon(
            onPressed: () {},
            size: M3EButtonSize.md,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        ),
        const SizedBox(width: 8),
        M3EButton(
          onPressed: () {},
          style: M3EButtonStyle.tonal,
          size: M3EButtonSize.md,
          tooltip: 'Archivar',
          semanticLabel: 'Archivar',
          child: const Icon(Icons.archive_outlined),
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

  /// Recent movements in this category — same grouped-card style.
  Widget _buildTransactions(BuildContext context) {
    final txs = category.transactions;
    return Column(
      children: [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) const SizedBox(height: kGroupSpacing),
          GroupedCard(
            borderRadius: groupedRadius(i, txs.length),
            onTap: () {},
            child: _MovementTile(tx: txs[i], currency: category.currency),
          ),
        ],
      ],
    );
  }
}

/// Reusable movement row content (icon, title + date, signed amount).
/// Mirrors the transaction tile from the accounts prototype.
class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.tx, required this.currency});

  final Transaction tx;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isExpense = tx.amountCents < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(tx.icon, size: 20, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: textTheme.bodyLarge),
                Text(
                  tx.date,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatMoney(tx.amountCents, currency),
            style: textTheme.titleSmall?.copyWith(
              color: isExpense ? colors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
