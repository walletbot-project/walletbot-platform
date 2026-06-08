import 'package:app/accounts/account_writes.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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

const _nameSuggestions = [
  (label: 'Efectivo', icon: Icons.payments_rounded),
  (label: 'Banco', icon: Icons.account_balance_rounded),
  (label: 'Tarjeta', icon: Icons.credit_card_rounded),
];

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  String _currency = 'ARS';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _applySuggestion(String name) {
    _nameController.text = name;
    _nameController.selection = TextSelection.collapsed(offset: name.length);
  }

  Future<void> _pickCurrency() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CurrencyPicker(selected: _currency),
    );
    if (picked != null) setState(() => _currency = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final rawBalance = _balanceController.text.trim();
    BigInt? initialAmountCents;
    if (rawBalance.isNotEmpty) {
      final parsed = double.tryParse(rawBalance.replaceAll(',', '.'));
      initialAmountCents = BigInt.from((parsed! * 100).round());
    }

    setState(() => _saving = true);
    try {
      final db = context.read<AppDatabase>();
      late final Account createdAccount;
      await db.transaction(() async {
        createdAccount = await createLocalAccount(
          db,
          name: _nameController.text.trim(),
          currency: _currency,
        );
        if (initialAmountCents != null) {
          final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
          await db.insertTransaction(
            id: const Uuid().v4(),
            type: 'balance_adjustment',
            name: 'Balance inicial',
            status: 'cleared',
            date: now,
            accountId: createdAccount.id,
            categoryId: '',
            amount: initialAmountCents,
            currency: _currency,
            balanceAfter: initialAmountCents,
          );
        }
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('Error creating account: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear la cuenta')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva cuenta')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Sugerencias', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _nameSuggestions)
                  ActionChip(
                    avatar: Icon(s.icon),
                    label: Text(s.label),
                    onPressed: () => _applySuggestion(s.label),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Efectivo, Banco Nación…',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickCurrency,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Moneda',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text(_currency),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Balance inicial (opcional)',
                hintText: '0.00',
                prefixText: '$_currency ',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                if (parsed == null || parsed < 0) {
                  return 'Ingresá un monto válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker({required this.selected});

  final String selected;

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
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
              c.$1.toLowerCase().contains(q) || c.$2.toLowerCase().contains(q),
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
