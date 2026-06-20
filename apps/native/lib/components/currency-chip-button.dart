import 'package:app/components/currency-picker.dart';
import 'package:flutter/material.dart';

/// A compact [ActionChip] that shows the current currency code and opens
/// [CurrencyPickerSheet] on tap.  Calls [onChanged] with the new code when
/// the user picks one; does nothing if the sheet is dismissed.
///
/// This widget is stateless — the parent is responsible for storing the
/// selected currency and passing it back as [currency].
///
/// ```dart
/// CurrencyChipButton(
///   currency: _currency,
///   onChanged: (code) => setState(() => _currency = code),
/// )
/// ```
class CurrencyChipButton extends StatelessWidget {
  const CurrencyChipButton({
    super.key,
    required this.currency,
    required this.onChanged,
  });

  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(currency),
      avatar: const Icon(Icons.arrow_drop_down, size: 18),
      tooltip: 'Cambiar moneda',
      onPressed: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => CurrencyPickerSheet(selected: currency),
        );
        if (picked != null && context.mounted) onChanged(picked);
      },
    );
  }
}
