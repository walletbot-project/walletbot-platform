import 'package:flutter/material.dart';

const _currencies = [
  (code: 'ARS', name: 'Peso Argentino'),
  (code: 'USD', name: 'Dólar Estadounidense'),
  (code: 'EUR', name: 'Euro'),
  (code: 'BRL', name: 'Real Brasileño'),
  (code: 'UYU', name: 'Peso Uruguayo'),
  (code: 'CLP', name: 'Peso Chileno'),
  (code: 'GBP', name: 'Libra Esterlina'),
];

/// A modal bottom sheet that lets the user pick a currency code.
/// Returns the selected code via [Navigator.pop]; returns nothing if dismissed.
///
/// The [selected] code is highlighted in the list.
///
/// ```dart
/// final picked = await showModalBottomSheet<String>(
///   context: context,
///   isScrollControlled: true,
///   showDragHandle: true,
///   builder: (_) => CurrencyPickerSheet(selected: currency),
/// );
/// ```
class CurrencyPickerSheet extends StatelessWidget {
  const CurrencyPickerSheet({super.key, required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Elegir moneda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final c in _currencies)
            ListTile(
              title: Text(c.code),
              subtitle: Text(c.name),
              trailing: c.code == selected
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
