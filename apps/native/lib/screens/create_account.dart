import 'package:app/components/account_icons.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/widgets/currency_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

List<({String label, IconData icon})> _nameSuggestions(AppLocalizations l10n) =>
    [
      (label: l10n.cash, icon: Icons.payments_rounded),
      (label: l10n.bank, icon: Icons.account_balance_rounded),
      (label: l10n.card, icon: Icons.credit_card_rounded),
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
  late String _currency;
  Color _color = accountDefaultColor;
  IconData _icon = accountDefaultIcon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currency = context.read<AppRepositories>().defaultCurrency();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _applySuggestion(({String label, IconData icon}) suggestion) {
    final name = suggestion.label;
    _nameController.text = name;
    _nameController.selection = TextSelection.collapsed(offset: name.length);
    setState(() => _icon = suggestion.icon);
  }

  Future<void> _pickCurrency() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CurrencyPicker(selected: _currency),
    );
    if (picked != null) setState(() => _currency = picked);
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: accountIconOptions,
      accent: _color,
    );
    if (picked != null) setState(() => _icon = picked);
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
      await context.read<AppRepositories>().accounts.create(
        name: _nameController.text.trim(),
        currency: _currency,
        color: colorToHex(_color),
        icon: accountIconName(_icon),
        initialBalanceCents: initialAmountCents,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('Error creating account: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.accountCreateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.newAccount)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.l10n.suggestions,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _nameSuggestions(context.l10n))
                  ActionChip(
                    avatar: Icon(s.icon),
                    label: Text(s.label),
                    onPressed: () => _applySuggestion(s),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.nameRequiredLabel,
                hintText: context.l10n.accountNameExample,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.l10n.enterName
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.iconAndColor,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tappable icon tile, tinted with the selected accent.
                InkWell(
                  onTap: _pickIcon,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon, size: 28, color: _color),
                  ),
                ),
                const SizedBox(width: 16),
                // Inline accent swatches.
                Expanded(
                  child: ColorPicker(
                    selected: _color,
                    options: colorOptions,
                    onChanged: (color) => setState(() => _color = color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickCurrency,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.l10n.currency,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
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
                labelText: context.l10n.initialBalanceOptional,
                hintText: '0.00',
                prefixText: '$_currency ',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                if (parsed == null || parsed < 0) {
                  return context.l10n.enterValidAmount;
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
                  : Text(context.l10n.createAccount),
            ),
          ],
        ),
      ),
    );
  }
}
