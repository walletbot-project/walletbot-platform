import 'package:app/components/color_utils.dart';
import 'package:flutter/material.dart';

/// A reusable swatch grid for picking an accent color. Renders the options from
/// [color_utils] (or a custom [options] palette) and highlights the [selected]
/// one. Stateless: the caller owns the selected value and reacts to [onChanged].
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.options = tagColorOptions,
  });

  final Color selected;
  final ValueChanged<Color> onChanged;
  final List<Color> options;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((color) {
        final isSelected = color == selected;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: isSelected ? const Icon(Icons.check, size: 18) : null,
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
  List<Color> options = tagColorOptions,
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Elegir color'),
        content: ColorPicker(
          selected: selected,
          options: options,
          onChanged: (color) => Navigator.of(dialogContext).pop(color),
        ),
      );
    },
  );
}
