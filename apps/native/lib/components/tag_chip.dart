import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';

/// Visual styling shared by every tag chip (the Insights tag list and the
/// transaction detail receipt) so they read identically in both themes.
///
/// The fill is always the tag's own identity color. The avatar and label adapt
/// per theme:
/// - Dark: a contrasting [foregroundOn] color, so text/icon stay legible on any
///   fill without changing the fill itself.
/// - Light: a white avatar with muted `onSurfaceVariant` label text.
///
/// The label style is always set explicitly (never left to the chip widget's
/// default), because different chip types — `ActionChip` vs `Chip`/`InputChip`
/// — default their label color differently (`onSurface` vs `onSurfaceVariant`),
/// which is what made the two screens look different.
typedef TagChipStyle = ({
  Color background,
  Color avatarColor,
  TextStyle? labelStyle,
});

TagChipStyle tagChipStyle(BuildContext context, Color color) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final labelColor = isDark
      ? foregroundOn(color)
      : theme.colorScheme.onSurfaceVariant;
  return (
    background: color,
    avatarColor: isDark ? foregroundOn(color) : Colors.white,
    labelStyle: theme.textTheme.labelLarge?.copyWith(color: labelColor),
  );
}
