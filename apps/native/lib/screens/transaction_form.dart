import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TransactionFormType { income, expense, transfer }

enum _TransferAmountField { source, destination }

class TransactionFormResult {
  const TransactionFormResult({
    required this.type,
    required this.accountName,
    required this.accountCurrency,
    this.destinationAccountName,
    this.destinationAccountCurrency,
    required this.date,
    required this.amount,
    this.destinationAmount,
    this.exchangeRate,
    required this.title,
    required this.description,
    required this.categoryName,
    required this.tags,
  });

  final TransactionFormType type;
  final String accountName;
  final String accountCurrency;
  final String? destinationAccountName;
  final String? destinationAccountCurrency;
  final DateTime date;
  final double amount;
  final double? destinationAmount;
  final double? exchangeRate;
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
  final _amountController = TextEditingController();
  final _destinationAmountController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();

  TransactionFormType _type = TransactionFormType.income;
  _MockAccount? _selectedAccount;
  _MockAccount? _selectedDestinationAccount;
  _MockCategory? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  final List<String> _tags = [];
  bool _isSaving = false;
  bool _isRecurringExpense = false;
  bool _updatingTransferAmounts = false;
  bool _sourceAmountTouched = false;
  bool _destinationAmountTouched = false;

  @override
  void dispose() {
    _amountController.dispose();
    _destinationAmountController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    _commitInlineEditing();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _pickAccount({bool destination = false}) async {
    _commitInlineEditing();
    final selectedAccount = destination
        ? _selectedDestinationAccount
        : _selectedAccount;
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
                  trailing: account == selectedAccount
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
    setState(() {
      if (destination) {
        _selectedDestinationAccount = account;
      } else {
        _selectedAccount = account;
      }
      _mirrorSameCurrencyTransferAmount(_TransferAmountField.source);
    });
  }

  Future<void> _pickCategory() async {
    _commitInlineEditing();
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

  void _commitInlineEditing() {
    _addTag(_tagController.text);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _submit() async {
    _commitInlineEditing();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final account = _selectedAccount;
    if (account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una cuenta')));
      return;
    }
    final destinationAccount = _selectedDestinationAccount;
    if (_type == TransactionFormType.transfer) {
      if (destinationAccount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una cuenta destino')),
        );
        return;
      }
      if (destinationAccount.name == account.name &&
          destinationAccount.currency == account.currency) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Origen y destino deben ser cuentas distintas'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final amount = _parseAmount(_amountController.text)!;
      final destinationAmount = _type == TransactionFormType.transfer
          ? _parseAmount(_destinationAmountController.text)
          : null;
      final exchangeRate =
          _shouldShowExchangeRate &&
              destinationAmount != null &&
              destinationAmount > 0
          ? destinationAmount / amount
          : null;
      final result = TransactionFormResult(
        type: _type,
        accountName: account.name,
        accountCurrency: account.currency,
        destinationAccountName: destinationAccount?.name,
        destinationAccountCurrency: destinationAccount?.currency,
        date: _selectedDate,
        amount: amount,
        destinationAmount: destinationAmount,
        exchangeRate: exchangeRate,
        title: _type == TransactionFormType.transfer
            ? 'Transferencia'
            : _titleController.text.trim(),
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
    final selectedColor = switch (_type) {
      TransactionFormType.income => Colors.greenAccent.shade400,
      TransactionFormType.expense => const Color(0xFFFF3744),
      TransactionFormType.transfer => const Color(0xFF6DE7D8),
    };

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
                    ButtonSegment(
                      value: TransactionFormType.transfer,
                      label: Text('Transferencia'),
                    ),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
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
                      : (selected) => _changeType(selected.first),
                ),
              ),
              const SizedBox(height: 36),
              if (_type == TransactionFormType.transfer)
                _TransferBlock(
                  sourceAccount: _selectedAccount,
                  destinationAccount: _selectedDestinationAccount,
                  amountController: _amountController,
                  destinationAmountController: _destinationAmountController,
                  enabled: !_isSaving,
                  onPickSource: () => _pickAccount(),
                  onPickDestination: () => _pickAccount(destination: true),
                  onSwap: _isSaving ? null : _swapTransferAccounts,
                  onAmountChanged: (_) {
                    _sourceAmountTouched = true;
                    _mirrorSameCurrencyTransferAmount(
                      _TransferAmountField.source,
                    );
                  },
                  onDestinationAmountChanged: (_) {
                    _destinationAmountTouched = true;
                    _mirrorSameCurrencyTransferAmount(
                      _TransferAmountField.destination,
                    );
                  },
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel('Cuenta'),
                          const SizedBox(height: 10),
                          _PickerChip(
                            label: _selectedAccount?.name ?? 'Seleccionar',
                            onPressed: _isSaving ? null : () => _pickAccount(),
                          ),
                        ],
                      ),
                    ),
                    if (_type == TransactionFormType.expense) ...[
                      const SizedBox(width: 16),
                      _RecurringExpenseControl(
                        value: _isRecurringExpense,
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _isRecurringExpense = value),
                      ),
                    ],
                  ],
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
              if (_type != TransactionFormType.transfer) ...[
                const SizedBox(height: 18),
                _AmountField(
                  controller: _amountController,
                  label: 'Monto',
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Titulo',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _isSaving ? null : _titleController.clear,
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Titulo es obligatorio';
                    }
                    return null;
                  },
                ),
              ],
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
                label: _selectedCategory?.name ?? 'Seleccionar',
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
                        backgroundColor: const Color(0xFFFFF4BE),
                        side: const BorderSide(color: Color(0xFFD7D0B8)),
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

  void _changeType(TransactionFormType type) {
    _commitInlineEditing();
    setState(() {
      _type = type;
      if (type == TransactionFormType.income) _isRecurringExpense = false;
      if (type == TransactionFormType.transfer) {
        _isRecurringExpense = false;
        _selectedCategory ??= _transferCategory;
        _mirrorSameCurrencyTransferAmount(_TransferAmountField.source);
      }
    });
  }

  bool get _shouldShowExchangeRate {
    final source = _selectedAccount;
    final destination = _selectedDestinationAccount;
    if (source == null || destination == null) return true;
    return source.currency != destination.currency;
  }

  void _mirrorSameCurrencyTransferAmount(_TransferAmountField changed) {
    if (_type != TransactionFormType.transfer ||
        _shouldShowExchangeRate ||
        _updatingTransferAmounts) {
      return;
    }
    _updatingTransferAmounts = true;
    try {
      switch (changed) {
        case _TransferAmountField.source:
          if (_destinationAmountTouched) return;
          _setControllerText(
            _destinationAmountController,
            _amountController.text,
          );
        case _TransferAmountField.destination:
          if (_sourceAmountTouched) return;
          _setControllerText(
            _amountController,
            _destinationAmountController.text,
          );
      }
    } finally {
      _updatingTransferAmounts = false;
    }
  }

  void _swapTransferAccounts() {
    setState(() {
      final source = _selectedAccount;
      _selectedAccount = _selectedDestinationAccount;
      _selectedDestinationAccount = source;
      final sourceAmount = _amountController.text;
      _setControllerText(_amountController, _destinationAmountController.text);
      _setControllerText(_destinationAmountController, sourceAmount);
      final sourceTouched = _sourceAmountTouched;
      _sourceAmountTouched = _destinationAmountTouched;
      _destinationAmountTouched = sourceTouched;
    });
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }
}

class _RecurringExpenseControl extends StatelessWidget {
  const _RecurringExpenseControl({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Gasto recurrente',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Transform.scale(
            scale: 0.86,
            child: SizedBox(
              height: 35,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferBlock extends StatelessWidget {
  const _TransferBlock({
    required this.sourceAccount,
    required this.destinationAccount,
    required this.amountController,
    required this.destinationAmountController,
    required this.enabled,
    required this.onPickSource,
    required this.onPickDestination,
    required this.onSwap,
    required this.onAmountChanged,
    required this.onDestinationAmountChanged,
  });

  final _MockAccount? sourceAccount;
  final _MockAccount? destinationAccount;
  final TextEditingController amountController;
  final TextEditingController destinationAmountController;
  final bool enabled;
  final VoidCallback onPickSource;
  final VoidCallback onPickDestination;
  final VoidCallback? onSwap;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDestinationAmountChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TransferSide(
            label: 'Sale',
            account: sourceAccount,
            amountController: amountController,
            enabled: enabled,
            onPickAccount: onPickSource,
            onAmountChanged: onAmountChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 34, 8, 0),
          child: IconButton.filledTonal(
            onPressed: onSwap,
            icon: const Icon(Icons.swap_horiz_rounded),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFE7FFFA),
              foregroundColor: Colors.black,
            ),
          ),
        ),
        Expanded(
          child: _TransferSide(
            label: 'Entra',
            account: destinationAccount,
            amountController: destinationAmountController,
            enabled: enabled,
            onPickAccount: onPickDestination,
            onAmountChanged: onDestinationAmountChanged,
          ),
        ),
      ],
    );
  }
}

class _TransferSide extends StatelessWidget {
  const _TransferSide({
    required this.label,
    required this.account,
    required this.amountController,
    required this.enabled,
    required this.onPickAccount,
    this.onAmountChanged,
  });

  final String label;
  final _MockAccount? account;
  final TextEditingController amountController;
  final bool enabled;
  final VoidCallback onPickAccount;
  final ValueChanged<String>? onAmountChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: amountController,
          enabled: enabled,
          textAlign: TextAlign.center,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
          ],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          ),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
          onChanged: onAmountChanged,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Obligatorio';
            final amount = _parseAmount(text);
            if (amount == null || amount <= 0) return 'Mayor a 0';
            return null;
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: _PickerChip(
            label: account == null
                ? 'Seleccionar'
                : '${account!.name} ${account!.currency}',
            onPressed: enabled ? onPickAccount : null,
          ),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
        suffixIcon: const Icon(Icons.cancel_outlined),
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

const _transferCategory = _MockCategory('Transferencia');

const _mockCategories = [
  _transferCategory,
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
