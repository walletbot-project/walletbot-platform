import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';
import 'package:app/l10n/l10n.dart';

/// A reusable swatch grid for picking an accent color. Renders the options from
/// [color_utils] (or a custom [options] palette) and highlights the [selected]
/// one. Stateless: the caller owns the selected value and reacts to [onChanged].
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.options = colorOptions,
  });

  final Color selected;
  final ValueChanged<Color> onChanged;
  final List<Color> options;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((color) {
        final isSelected = color == selected;
        // Preview the accent as entities paint it in this theme (see
        // [readableAccent]); selection still compares the stored option.
        final fill = readableAccent(color, brightness);

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
                    color: brightness == Brightness.dark
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
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(context.l10n.chooseColor),
        content: ColorPicker(
          selected: selected,
          options: options,
          onChanged: (color) => Navigator.of(dialogContext).pop(color),
        ),
      );
    },
  );
}
