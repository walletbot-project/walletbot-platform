import 'package:app/components/grouped_card.dart';
import 'package:flutter/material.dart';
import 'package:app/l10n/l10n.dart';

/// A single category rendered as a Material 3 expressive card-like list tile:
/// accent icon avatar, name, a movement-count subtitle, and a trailing chevron.
/// Mirrors the account tile layout. The grouped-card shape and tap behavior are
/// injected by the caller.
class CategoryListTile extends StatelessWidget {
  const CategoryListTile({
    super.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.usageCount,
    required this.borderRadius,
    this.onTap,
  });

  final String name;
  final IconData icon; // visual accent
  final Color color; // visual accent
  final int usageCount; // # of movements in this category
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.l10n.movementCount(usageCount),
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
