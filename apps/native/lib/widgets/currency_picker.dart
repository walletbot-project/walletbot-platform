import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';

// ISO 4217 codes — language-neutral and sorted alphabetically. Mirrored from
// `packages/shared/src/currencies.ts` (Dart can't import that package, so
// keep both lists in sync manually).
const currencies = [
  'AED',
  'ARS',
  'AUD',
  'BOB',
  'BRL',
  'CAD',
  'CHF',
  'CLP',
  'CNY',
  'COP',
  'CRC',
  'CUP',
  'DKK',
  'DOP',
  'EGP',
  'EUR',
  'GBP',
  'GTQ',
  'HKD',
  'HNL',
  'HUF',
  'IDR',
  'ILS',
  'INR',
  'JPY',
  'KRW',
  'MXN',
  'MYR',
  'NGN',
  'NIO',
  'NOK',
  'NZD',
  'PAB',
  'PEN',
  'PHP',
  'PKR',
  'PLN',
  'PYG',
  'RON',
  'RUB',
  'SAR',
  'SEK',
  'SGD',
  'THB',
  'TRY',
  'TWD',
  'UAH',
  'USD',
  'UYU',
  'VES',
  'VND',
  'ZAR',
];

const suggestedCurrencies = ['ARS', 'USD', 'EUR', 'BRL'];

/// Bundled fail-open default, used until the user's actual default currency
/// (device cache or backend) resolves. Mirrors `DEFAULT_CURRENCY` in
/// `packages/shared/src/currencies.ts`.
const kDefaultCurrency = 'ARS';

/// Currency chooser bottom sheet: search box + "most used" chips + full list.
/// Shared by account creation and the default-currency setting.
class CurrencyPicker extends StatefulWidget {
  const CurrencyPicker({super.key, required this.selected});

  final String selected;

  @override
  State<CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<CurrencyPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return currencies;
    final q = _query.toLowerCase();
    return currencies.where((code) => code.toLowerCase().contains(q)).toList();
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
              context.l10n.chooseCurrency,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.searchCurrency,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                context.l10n.mostUsed,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final code in suggestedCurrencies)
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
                  final code = filtered[i];
                  return ListTile(
                    dense: true,
                    title: Text(code),
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
