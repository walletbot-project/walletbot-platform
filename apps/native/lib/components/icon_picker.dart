import 'package:flutter/material.dart';
import 'package:app/l10n/l10n.dart';

/// A reusable grid for picking an entity icon. Renders the provided [options]
/// and highlights the [selected] one, tinted with [accent]. Stateless: the
/// caller owns the selected value and reacts to [onChanged].
class IconPicker extends StatelessWidget {
  const IconPicker({
    super.key,
    required this.selected,
    required this.options,
    required this.accent,
    required this.onChanged,
  });

  final IconData selected;
  final List<IconData> options;
  final Color accent;
  final ValueChanged<IconData> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.map((icon) {
        final isSelected = icon == selected;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(icon),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.28)
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 26,
              color: isSelected ? accent : colors.onSurfaceVariant,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Opens [IconPicker] in a popup dialog and resolves to the chosen icon
/// (or `null` if dismissed).
Future<IconData?> showIconPickerDialog(
  BuildContext context, {
  required IconData selected,
  required List<IconData> options,
  required Color accent,
}) {
  return showDialog<IconData>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(context.l10n.chooseIcon),
        content: SingleChildScrollView(
          child: IconPicker(
            selected: selected,
            options: options,
            accent: accent,
            onChanged: (icon) => Navigator.of(dialogContext).pop(icon),
          ),
        ),
      );
    },
  );
}
