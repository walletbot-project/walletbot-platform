import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TransactionFormType { income, expense }

class TransactionFormResult {
  const TransactionFormResult({
    required this.type,
    required this.accountName,
    required this.accountCurrency,
    required this.date,
    required this.amount,
    required this.title,
    required this.description,
    required this.categoryName,
    required this.tags,
  });

  final TransactionFormType type;
  final String accountName;
  final String accountCurrency;
  final DateTime date;
  final double amount;
  final String title;
  final String? description;
  final String? categoryName;
  final List<String> tags;
}

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '400');
  final _descriptionController = TextEditingController(text: 'Intereses MP');
  final _tagController = TextEditingController();

  TransactionFormType _type = TransactionFormType.income;
  _MockAccount _selectedAccount = _mockAccounts.first;
  _MockCategory? _selectedCategory = _mockCategories.first;
  DateTime _selectedDate = DateTime.now();
  final List<String> _tags = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _pickAccount() async {
    final account = await showModalBottomSheet<_MockAccount>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final account in _mockAccounts)
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded),
                  title: Text(account.name),
                  subtitle: Text(account.currency),
                  trailing: account == _selectedAccount
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, account),
                ),
            ],
          ),
        );
      },
    );
    if (account == null || !mounted) return;
    setState(() => _selectedAccount = account);
  }

  Future<void> _pickCategory() async {
    final selection = await showModalBottomSheet<_CategorySelection>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: const Text('Sin categoria'),
                trailing: _selectedCategory == null
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () =>
                    Navigator.pop(context, const _CategorySelection.none()),
              ),
              for (final category in _mockCategories)
                ListTile(
                  leading: const Icon(Icons.label_rounded),
                  title: Text(category.name),
                  trailing: category == _selectedCategory
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.pop(
                    context,
                    _CategorySelection.category(category),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (selection == null || !mounted) return;
    setState(() => _selectedCategory = selection.category);
  }

  void _addTag(String rawValue) {
    final name = rawValue.trim();
    if (name.isEmpty) return;
    final exists = _tags.any((tag) => tag.toLowerCase() == name.toLowerCase());
    if (exists) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(name);
      _tagController.clear();
    });
  }

  Future<void> _submit() async {
    _addTag(_tagController.text);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final amount = _parseAmount(_amountController.text)!;
      final result = TransactionFormResult(
        type: _type,
        accountName: _selectedAccount.name,
        accountCurrency: _selectedAccount.currency,
        date: _selectedDate,
        amount: amount,
        title: _emptyToNull(_descriptionController.text) ?? 'Movimiento',
        description: _emptyToNull(_descriptionController.text),
        categoryName: _selectedCategory?.name,
        tags: List.unmodifiable(_tags),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Movimiento anotado')),
      );
      navigator.pop(result);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo anotar: $error')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedColor = _type == TransactionFormType.income
        ? Colors.greenAccent.shade400
        : colorScheme.errorContainer;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 120),
            children: [
              Text(
                'Anadir movimiento',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: SegmentedButton<TransactionFormType>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionFormType.income,
                      label: Text('Ingreso'),
                    ),
                    ButtonSegment(
                      value: TransactionFormType.expense,
                      label: Text('Gasto'),
                    ),
                  ],
                  selected: {_type},
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return selectedColor;
                      }
                      return Colors.transparent;
                    }),
                    foregroundColor: const WidgetStatePropertyAll(Colors.black),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  onSelectionChanged: _isSaving
                      ? null
                      : (selected) => setState(() => _type = selected.first),
                ),
              ),
              const SizedBox(height: 36),
              _SectionLabel('Cuenta'),
              const SizedBox(height: 10),
              _PickerChip(
                label: _selectedAccount.name,
                onPressed: _isSaving ? null : _pickAccount,
              ),
              const SizedBox(height: 24),
              _ReadonlyField(
                label: 'Fecha',
                value: _formatDate(_selectedDate),
                icon: Icons.calendar_month_rounded,
                onTap: _isSaving ? null : _pickDate,
                onClear: _isSaving
                    ? null
                    : () => setState(() => _selectedDate = DateTime.now()),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _amountController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.cancel_outlined),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Monto es obligatorio';
                  final amount = _parseAmount(text);
                  if (amount == null || amount <= 0) {
                    return 'Monto debe ser mayor a 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _descriptionController,
                enabled: !_isSaving,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Descripcion',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _isSaving ? null : _descriptionController.clear,
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _SectionLabel('Categoria'),
              const SizedBox(height: 10),
              _PickerChip(
                label: _selectedCategory?.name ?? 'Sin categoria',
                onPressed: _isSaving ? null : _pickCategory,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _tagController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'Etiquetas',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => _addTag(_tagController.text),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                onFieldSubmitted: _addTag,
                onChanged: (value) {
                  if (value.endsWith(',')) {
                    _addTag(value.substring(0, value.length - 1));
                  }
                },
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: _isSaving
                            ? null
                            : () => setState(() => _tags.remove(tag)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFF0C9CE),
                  foregroundColor: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Anotar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF21C4B6),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: Colors.black,
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.55,
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF21C4B6),
            foregroundColor: Colors.white,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          suffixIcon: IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.cancel_outlined),
          ),
        ),
        child: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _MockAccount {
  const _MockAccount({required this.name, required this.currency});

  final String name;
  final String currency;
}

class _MockCategory {
  const _MockCategory(this.name);

  final String name;
}

class _CategorySelection {
  const _CategorySelection.category(this.category);

  const _CategorySelection.none() : category = null;

  final _MockCategory? category;
}

const _mockAccounts = [
  _MockAccount(name: 'Mercado Pago', currency: 'ARS'),
  _MockAccount(name: 'Efectivo', currency: 'ARS'),
  _MockAccount(name: 'USD', currency: 'USD'),
];

const _mockCategories = [
  _MockCategory('Intereses'),
  _MockCategory('Comida'),
  _MockCategory('Transporte'),
  _MockCategory('Entretenimiento'),
  _MockCategory('Otros'),
];

double? _parseAmount(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.'));
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
