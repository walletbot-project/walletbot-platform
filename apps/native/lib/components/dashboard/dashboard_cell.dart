import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';

/// Shared visual shell for dashboard widgets. Cells read like compact Material
/// list/grid items: small radius and subtle surface tint.
class DashboardCell extends StatelessWidget {
  const DashboardCell({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(16),
    this.minHeight = 120,
    this.bodySpacing = 12,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final double bodySpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolvedTitle = title.isEmpty ? 'Widget' : title;
    // No custom color: the M3 surfaceContainer role separates from the scaffold
    // (surface) consistently in both themes: darker than the background in
    // light, lighter in dark. A defined color is a stored light pastel, adapted
    // per theme so its content stays legible (see [readableWidgetBackground]).
    final cellColor = backgroundColor == null
        ? colors.surfaceContainer
        : readableWidgetBackground(backgroundColor!, theme.brightness);
    final resolvedPadding = padding.resolve(Directionality.of(context));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cellColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          children: [
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          resolvedTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
                  SizedBox(height: bodySpacing),
                  child,
                ],
              ),
            ),
            // Floats in the bottom-left corner without affecting layout.
            if (icon != null)
              Positioned(
                left: resolvedPadding.left,
                bottom: resolvedPadding.bottom,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 13,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
