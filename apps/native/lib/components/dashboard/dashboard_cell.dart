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
    final cellColor =
        backgroundColor ??
        Color.alphaBlend(
          colors.primary.withValues(alpha: 0.04),
          colors.surface,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cellColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
      ),
    );
  }
}
