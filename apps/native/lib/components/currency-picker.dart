import 'package:flutter/material.dart';

// (ISO code, Spanish name) — sorted alphabetically by code
const _currencies = [
  ('AED', 'Dírham emiratí'),
  ('ARS', 'Peso argentino'),
  ('AUD', 'Dólar australiano'),
  ('BOB', 'Boliviano'),
  ('BRL', 'Real brasileño'),
  ('CAD', 'Dólar canadiense'),
  ('CHF', 'Franco suizo'),
  ('CLP', 'Peso chileno'),
  ('CNY', 'Yuan chino'),
  ('COP', 'Peso colombiano'),
  ('CRC', 'Colón costarricense'),
  ('CUP', 'Peso cubano'),
  ('DKK', 'Corona danesa'),
  ('DOP', 'Peso dominicano'),
  ('EGP', 'Libra egipcia'),
  ('EUR', 'Euro'),
  ('GBP', 'Libra esterlina'),
  ('GTQ', 'Quetzal guatemalteco'),
  ('HKD', 'Dólar de Hong Kong'),
  ('HNL', 'Lempira hondureño'),
  ('HUF', 'Forinto húngaro'),
  ('IDR', 'Rupia indonesia'),
  ('ILS', 'Séquel israelí'),
  ('INR', 'Rupia india'),
  ('JPY', 'Yen japonés'),
  ('KRW', 'Won surcoreano'),
  ('MXN', 'Peso mexicano'),
  ('MYR', 'Ringgit malayo'),
  ('NGN', 'Naira nigeriana'),
  ('NIO', 'Córdoba nicaragüense'),
  ('NOK', 'Corona noruega'),
  ('NZD', 'Dólar neozelandés'),
  ('PAB', 'Balboa panameño'),
  ('PEN', 'Sol peruano'),
  ('PHP', 'Peso filipino'),
  ('PKR', 'Rupia pakistaní'),
  ('PLN', 'Esloti polaco'),
  ('PYG', 'Guaraní paraguayo'),
  ('RON', 'Leu rumano'),
  ('RUB', 'Rublo ruso'),
  ('SAR', 'Riyal saudí'),
  ('SEK', 'Corona sueca'),
  ('SGD', 'Dólar singapurense'),
  ('THB', 'Baht tailandés'),
  ('TRY', 'Lira turca'),
  ('TWD', 'Nuevo dólar taiwanés'),
  ('UAH', 'Grivna ucraniana'),
  ('USD', 'Dólar estadounidense'),
  ('UYU', 'Peso uruguayo'),
  ('VES', 'Bolívar venezolano'),
  ('VND', 'Dong vietnamita'),
  ('ZAR', 'Rand sudafricano'),
];

const _suggestedCurrencies = ['ARS', 'USD', 'EUR', 'BRL'];

/// Bottom-sheet content for picking a currency ISO code.
///
/// Call via [showModalBottomSheet]; the sheet pops with the selected ISO code
/// when the user makes a choice, or pops with `null` on dismiss.
///
/// ```dart
/// final picked = await showModalBottomSheet<String>(
///   context: context,
///   isScrollControlled: true,
///   showDragHandle: true,
///   builder: (_) => CurrencyPickerSheet(selected: currentCurrency),
/// );
/// if (picked != null) { /* apply picked */ }
/// ```
class CurrencyPickerSheet extends StatefulWidget {
  const CurrencyPickerSheet({super.key, required this.selected});

  final String selected;

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<(String, String)> get _filtered {
    if (_query.isEmpty) return _currencies;
    final q = _query.toLowerCase();
    return _currencies
        .where(
          (c) =>
              c.$1.toLowerCase().contains(q) ||
              c.$2.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elegí una moneda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar moneda…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Más usadas',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final code in _suggestedCurrencies)
                    FilterChip(
                      label: Text(code),
                      selected: widget.selected == code,
                      onSelected: (_) => Navigator.of(context).pop(code),
                    ),
                ],
              ),
              const Divider(height: 24),
            ] else
              const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final (code, name) = filtered[i];
                  return ListTile(
                    dense: true,
                    title: Text(code),
                    subtitle: Text(name),
                    selected: widget.selected == code,
                    onTap: () => Navigator.of(context).pop(code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
