import 'package:app/screens/accounts_prototype.dart';
import 'package:flutter/material.dart';
import 'package:m3e_buttons/m3e_buttons.dart';

/// Mock tag model shaped after the real backend fields:
/// name, optional description, optional parentId (here modelled as nested
/// `subtags`), optional color accent, isArchived. Usage stats (count + total)
/// are prototype-only, computed from movements tagged with this tag.
/// Monetary values are in cents (matching the backend `amount` convention).
class Tag {
  const Tag({
    required this.name,
    required this.icon,
    required this.color,
    this.description,
    this.subtags = const [],
    required this.usageCount,
    required this.totalCents,
    this.currency = 'USD',
    this.transactions = _sampleTagTransactions,
  });

  final String name;
  final IconData icon;
  final Color color; // backend `color` hex
  final String? description; // backend `description`
  final List<Tag> subtags; // children via backend `parentId`
  final int usageCount; // # of movements with this tag (prototype stat)
  final int totalCents; // accumulated amount across tagged movements
  final String currency; // ISO code for the total
  final List<Transaction> transactions; // most-recent first
}

/// Shared mock movements reused across tags for the prototype.
const List<Transaction> _sampleTagTransactions = [
  Transaction(
    title: 'Supermercado',
    date: '24 may',
    amountCents: -8450,
    icon: Icons.shopping_cart_rounded,
  ),
  Transaction(
    title: 'Café',
    date: '24 may',
    amountCents: -1200,
    icon: Icons.local_cafe_rounded,
  ),
  Transaction(
    title: 'Cena',
    date: '22 may',
    amountCents: -6200,
    icon: Icons.restaurant_rounded,
  ),
  Transaction(
    title: 'Delivery',
    date: '21 may',
    amountCents: -3400,
    icon: Icons.delivery_dining_rounded,
  ),
];

const List<Tag> _mockTags = [
  Tag(
    name: 'Comida',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFF59E0B),
    description: 'Todo lo relacionado a alimentación',
    usageCount: 42,
    totalCents: 184500,
    subtags: [
      Tag(
        name: 'Restaurantes',
        icon: Icons.restaurant_menu_rounded,
        color: Color(0xFFF59E0B),
        usageCount: 18,
        totalCents: 96200,
      ),
      Tag(
        name: 'Supermercado',
        icon: Icons.shopping_cart_rounded,
        color: Color(0xFFF59E0B),
        usageCount: 15,
        totalCents: 62100,
      ),
      Tag(
        name: 'Delivery',
        icon: Icons.delivery_dining_rounded,
        color: Color(0xFFF59E0B),
        usageCount: 9,
        totalCents: 26200,
      ),
    ],
  ),
  Tag(
    name: 'Transporte',
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF3B82F6),
    description: 'Movilidad y viajes cortos',
    usageCount: 27,
    totalCents: 73200,
    subtags: [
      Tag(
        name: 'Combustible',
        icon: Icons.local_gas_station_rounded,
        color: Color(0xFF3B82F6),
        usageCount: 12,
        totalCents: 48000,
      ),
      Tag(
        name: 'Taxi / App',
        icon: Icons.local_taxi_rounded,
        color: Color(0xFF3B82F6),
        usageCount: 15,
        totalCents: 25200,
      ),
    ],
  ),
  Tag(
    name: 'Ocio',
    icon: Icons.celebration_rounded,
    color: Color(0xFF8B5CF6),
    description: 'Entretenimiento y tiempo libre',
    usageCount: 19,
    totalCents: 58900,
    subtags: [
      Tag(
        name: 'Streaming',
        icon: Icons.subscriptions_rounded,
        color: Color(0xFF8B5CF6),
        usageCount: 6,
        totalCents: 5994,
      ),
      Tag(
        name: 'Cine',
        icon: Icons.movie_rounded,
        color: Color(0xFF8B5CF6),
        usageCount: 4,
        totalCents: 12000,
      ),
    ],
  ),
  Tag(
    name: 'Hogar',
    icon: Icons.home_rounded,
    color: Color(0xFF14B8A6),
    description: 'Gastos del día a día en casa',
    usageCount: 31,
    totalCents: 142300,
  ),
  Tag(
    name: 'Salud',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEF4444),
    usageCount: 8,
    totalCents: 39800,
  ),
];

// M3 expressive grouped-list shape tokens — mirror the accounts prototype so
// every card list across the app reads with the same shape language.
const double _kGroupOuterRadius = 24; // first/last ends of a group
const double _kGroupInnerRadius = 4; // corners between adjacent cards
const double _kGroupSpacing = 2; // small separation between cards
const double _kSubtagIndent = 20; // left inset that signals hierarchy

/// Corner shape for the card at [index] within a group of [count]: large radius
/// on the outer ends of the group, minimal radius on the inner seams.
BorderRadius _groupedRadius(int index, int count) => BorderRadius.vertical(
  top: Radius.circular(index == 0 ? _kGroupOuterRadius : _kGroupInnerRadius),
  bottom: Radius.circular(
    index == count - 1 ? _kGroupOuterRadius : _kGroupInnerRadius,
  ),
);

class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiquetas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openTagSheet(_mockTags[0]),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        itemCount: _mockTags.length,
        // Larger gap between separate parent groups; cards inside a parent
        // group are joined by the 2dp seam internally.
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _TagGroup(tag: _mockTags[index], onOpen: _openTagSheet);
        },
      ),
    );
  }

  /// Opens the tag details as a draggable, scrollable modal sheet.
  void _openTagSheet(Tag tag) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // let the sheet grow taller than half-screen
      showDragHandle: true,
      builder: (_) => TagDetailsSheet(tag: tag),
    );
  }
}

/// A parent tag and its subtags rendered as one cohesive M3 expressive grouped
/// list: the parent card on top, each subtag joined below by the 2dp seam and
/// inset to signal hierarchy. Large radius lands only on the group's outer ends.
class _TagGroup extends StatelessWidget {
  const _TagGroup({required this.tag, required this.onOpen});

  final Tag tag;
  final void Function(Tag) onOpen;

  @override
  Widget build(BuildContext context) {
    final count = 1 + tag.subtags.length;
    return Column(
      children: [
        GroupedCard(
          borderRadius: _groupedRadius(0, count),
          onTap: () => onOpen(tag),
          child: _TagTileContent(tag: tag),
        ),
        for (var i = 0; i < tag.subtags.length; i++) ...[
          const SizedBox(height: _kGroupSpacing),
          GroupedCard(
            borderRadius: _groupedRadius(i + 1, count),
            onTap: () => onOpen(tag.subtags[i]),
            child: _TagTileContent(tag: tag.subtags[i], isSubtag: true),
          ),
        ],
      ],
    );
  }
}

/// Reusable tag row content (color chip, name + usage, total amount). When
/// [isSubtag] it is inset and uses a smaller dot to read as a child.
class _TagTileContent extends StatelessWidget {
  const _TagTileContent({required this.tag, this.isSubtag = false});

  final Tag tag;
  final bool isSubtag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isSubtag ? _kSubtagIndent + 16 : 16,
        14,
        16,
        14,
      ),
      child: Row(
        children: [
          if (isSubtag)
            // Small color dot — a lightweight leading marker for children.
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 14),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tag.color,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            // Parent: tinted rounded-square icon tile in the tag's accent.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tag.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(tag.icon, size: 22, color: tag.color),
            ),
          if (!isSubtag) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.name,
                  style: isSubtag ? textTheme.bodyMedium : textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${tag.usageCount} movimientos',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatMoney(-tag.totalCents, tag.currency),
            style: (isSubtag ? textTheme.titleSmall : textTheme.titleMedium)
                ?.copyWith(color: colors.error),
          ),
        ],
      ),
    );
  }
}

/// Draggable, scrollable modal sheet showing a tag's details.
class TagDetailsSheet extends StatelessWidget {
  const TagDetailsSheet({super.key, required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final hasSubtags = tag.subtags.isNotEmpty;
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
            if (hasSubtags) ...[
              const SizedBox(height: 28),
              _SectionHeader(title: 'Sub-etiquetas', action: 'Agregar'),
              const SizedBox(height: 8),
              _buildSubtags(context),
            ],
            const SizedBox(height: 28),
            _SectionHeader(title: 'Últimos movimientos', action: 'Ver todos'),
            const SizedBox(height: 8),
            _buildTransactions(context),
          ],
        );
      },
    );
  }

  /// Identity + usage as one cohesive M3 Expressive containment group: a
  /// color-washed identity hero (icon, name, optional description, color
  /// swatch) joined by the 2dp seam to the usage hero (total + count).
  Widget _buildIdentityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Material(
          color: tag.color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(_kGroupOuterRadius),
            bottom: Radius.circular(_kGroupInnerRadius),
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
                    color: tag.color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Icon(tag.icon, size: 30, color: tag.color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tag.name,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tag.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          tag.description!,
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
                const SizedBox(width: 12),
                // Discrete color swatch — the editable "color" attribute.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tag.color,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: _kGroupSpacing),
        // Usage hero — total accumulated and movement count.
        GroupedCard(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(_kGroupInnerRadius),
            bottom: Radius.circular(_kGroupOuterRadius),
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
                        'TOTAL',
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatMoney(-tag.totalCents, tag.currency),
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${tag.usageCount} movs.',
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Tag actions as Material 3 Expressive buttons: edit, archive, delete.
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

  /// Subtags as an M3 expressive grouped-card list, matching the parent list.
  Widget _buildSubtags(BuildContext context) {
    final subtags = tag.subtags;
    return Column(
      children: [
        for (var i = 0; i < subtags.length; i++) ...[
          if (i > 0) const SizedBox(height: _kGroupSpacing),
          GroupedCard(
            borderRadius: _groupedRadius(i, subtags.length),
            onTap: () {},
            child: _TagTileContent(tag: subtags[i], isSubtag: true),
          ),
        ],
      ],
    );
  }

  /// Recent movements tagged with this tag — same grouped-card style.
  Widget _buildTransactions(BuildContext context) {
    final txs = tag.transactions;
    return Column(
      children: [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) const SizedBox(height: _kGroupSpacing),
          GroupedCard(
            borderRadius: _groupedRadius(i, txs.length),
            onTap: () {},
            child: _MovementTile(tx: txs[i], currency: tag.currency),
          ),
        ],
      ],
    );
  }
}

/// Section header with a trailing text action — shared by subtags and movements.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(title, style: textTheme.titleMedium)),
        TextButton(onPressed: () {}, child: Text(action)),
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
