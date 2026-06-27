import 'package:flutter/material.dart';

// M3 expressive grouped-list shape tokens (shared by every card list).
const double kGroupOuterRadius = 24; // first/last ends of a group
const double kGroupInnerRadius = 4; // corners between adjacent cards
const double kGroupSpacing = 2; // small separation between cards

/// Corner shape for the card at [index] within a group of [count]: large radius
/// on the outer ends of the group, minimal radius on the inner seams.
BorderRadius groupedRadius(int index, int count) => BorderRadius.vertical(
  top: Radius.circular(index == 0 ? kGroupOuterRadius : kGroupInnerRadius),
  bottom: Radius.circular(
    index == count - 1 ? kGroupOuterRadius : kGroupInnerRadius,
  ),
);

/// A single card within an M3 expressive grouped list: card surface, injected
/// corner shape, optional tap ripple. Reused by every card list on this screen.
class GroupedCard extends StatelessWidget {
  const GroupedCard({
    super.key,
    required this.borderRadius,
    required this.child,
    this.onTap,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}
