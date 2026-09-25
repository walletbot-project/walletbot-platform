import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';
import 'package:app/l10n/l10n.dart';

/// A reusable swatch grid for picking an accent color. Renders the options from
/// [color_utils] (or a custom [options] palette) and highlights the [selected]
/// one. Stateless: the caller owns the selected value and reacts to [onChanged].
///
/// With [themed], each swatch previews the accent as accounts and categories
/// paint it in the current theme (see [readableAccent]); tags paint their raw
/// color, so their pickers leave it off.
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.options = colorOptions,
    this.themed = false,
  });

  final Color selected;
  final ValueChanged<Color> onChanged;
  final List<Color> options;
  final bool themed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((color) {
        final isSelected = color == selected;
        // Selection still compares the stored option, never the preview.
        final fill = themed ? readableAccent(color, brightness) : color;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: themed && brightness == Brightness.dark
                        ? foregroundOn(fill)
                        : null,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}

/// Opens [ColorPicker] in a popup dialog and resolves to the chosen color
/// (or `null` if dismissed).
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required Color selected,
  List<Color> options = colorOptions,
  bool themed = false,
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(context.l10n.chooseColor),
        content: ColorPicker(
          selected: selected,
          options: options,
          themed: themed,
          onChanged: (color) => Navigator.of(dialogContext).pop(color),
        ),
      );
    },
  );
}
