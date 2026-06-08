import 'dart:async';

import 'package:app/components/color_utils.dart';
import 'package:app/database.dart';
import 'package:app/tags/tag_writes.dart';
import 'package:app/transactions/manual_transaction_writes.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum TransactionFormType { income, expense, transfer }

enum _TransferAmountField { source, destination }

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController _amountController = TextEditingController();
  TextEditingController _destinationAmountController = TextEditingController();
  TextEditingController _titleController = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  TextEditingController _tagController = TextEditingController();

  TransactionFormType _type = TransactionFormType.income;
  AppDatabase? _db;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  final List<Account> _mockAccounts = [];
  final List<Category> _mockCategories = [];
  List<_FormTag> _knownTags = const [];
  Account? _selectedAccount;
  Account? _selectedDestinationAccount;
  Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  final List<_FormTag> _tags = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRecurringExpense = false;
  bool _updatingTransferAmounts = false;
  bool _sourceAmountTouched = false;
  bool _destinationAmountTouched = false;

  List<Account> get _accountOptions => [..._accounts, ..._mockAccounts];

  List<Category> get _categoryOptions => [..._categories, ..._mockCategories];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = context.read<AppDatabase>();
    if (_db == db) return;
    _db = db;
    unawaited(_loadFormData(db));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _destinationAmountController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData(AppDatabase db) async {
    setState(() => _isLoading = true);
    final accounts =
        await (db.select(db.accounts)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt)]))
            .get();
    final categories =
        await (db.select(db.categories)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt)]))
            .get();
    final tags =
        await (db.select(db.tags)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt)]))
            .get();

    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
      _knownTags = tags
          .map(
            (tag) => _FormTag(
              id: tag.id,
              name: tag.name,
              color: colorFromHex(tag.color),
            ),
          )
          .toList();
      _selectedAccount = _resolveSelectedAccount(
        current: _selectedAccount,
        accounts: _accountOptions,
      );
      _selectedDestinationAccount = _resolveDestinationAccount(
        current: _selectedDestinationAccount,
        accounts: _accountOptions,
        source: _selectedAccount,
      );
      _selectedCategory = _resolveSelectedCategory(
        current: _selectedCategory,
        categories: _categoryOptions,
        type: _type,
      );
      _isLoading = false;
    });
  }

  Account? _resolveSelectedAccount({
    required Account? current,
    required List<Account> accounts,
  }) {
    if (accounts.isEmpty) return null;
    if (current != null) {
      for (final account in accounts) {
        if (account.id == current.id) return account;
      }
    }
    return accounts.first;
  }

  Account? _resolveDestinationAccount({
    required Account? current,
    required List<Account> accounts,
    required Account? source,
  }) {
    if (accounts.isEmpty) return null;
    if (current != null) {
      for (final account in accounts) {
        if (account.id == current.id) return account;
      }
    }
    if (source == null) return accounts.first;
    for (final account in accounts) {
      if (account.id != source.id) return account;
    }
    return source;
  }

  Category? _resolveSelectedCategory({
    required Category? current,
    required List<Category> categories,
    required TransactionFormType type,
  }) {
    if (categories.isEmpty) return null;
    if (current != null) {
      for (final category in categories) {
        if (category.id == current.id) return category;
      }
    }

    if (type == TransactionFormType.transfer) {
      for (final category in categories) {
        if (category.name.toLowerCase() == 'transferencia') return category;
      }
    }

    return categories.first;
  }

  Future<void> _pickDate() async {
    await _commitInlineEditing();
    if (!mounted) return;
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
    await _commitInlineEditing();
    if (!mounted) return;
    final selectedAccount = destination
        ? _selectedDestinationAccount
        : _selectedAccount;
    final account = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Nueva cuenta'),
                onTap: () async {
                  final created = await _createMockAccountDialog();
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                },
              ),
              for (final account in _accountOptions)
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
    await _commitInlineEditing();
    if (!mounted) return;
    final category = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Nueva categoria'),
                onTap: () async {
                  final created = await _createMockCategoryDialog();
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                },
              ),
              for (final category in _categoryOptions)
                ListTile(
                  leading: const Icon(Icons.label_rounded),
                  title: Text(category.name),
                  trailing: category == _selectedCategory
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, category),
                ),
            ],
          ),
        );
      },
    );
    if (category == null || !mounted) return;
    setState(() => _selectedCategory = category);
  }

  Future<void> _addTag(String rawValue) async {
    final name = rawValue.trim();
    if (name.isEmpty) return;
    final alreadySelected = _tags.any(
      (tag) => tag.name.toLowerCase() == name.toLowerCase(),
    );
    if (alreadySelected) {
      _tagController.clear();
      return;
    }

    final existingTag = _findKnownTag(name);
    if (existingTag != null) {
      setState(() {
        _tags.add(existingTag);
        _tagController.clear();
      });
      return;
    }

    final color = await _pickNewTagColor(name);
    if (color == null || !mounted) return;
    final tag = _FormTag(name: name, color: color);
    setState(() {
      _knownTags = [..._knownTags, tag];
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _commitInlineEditing() async {
    await _addTag(_tagController.text);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  _FormTag? _findKnownTag(String name) {
    final normalized = name.toLowerCase();
    for (final tag in _knownTags) {
      if (tag.name.toLowerCase() == normalized) return tag;
    }
    return null;
  }

  Future<void> _pickExistingTag() async {
    await _commitInlineEditing();
    if (!mounted) return;
    final availableTags = _knownTags
        .where(
          (tag) => !_tags.any(
            (selected) => selected.name.toLowerCase() == tag.name.toLowerCase(),
          ),
        )
        .toList();
    final tag = await showModalBottomSheet<_FormTag>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (availableTags.isEmpty)
                const ListTile(title: Text('No hay etiquetas disponibles')),
              for (final tag in availableTags)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: tag.color,
                    radius: 12,
                    child: const SizedBox.shrink(),
                  ),
                  title: Text(tag.name),
                  onTap: () => Navigator.pop(context, tag),
                ),
            ],
          ),
        );
      },
    );
    if (tag == null || !mounted) return;
    setState(() => _tags.add(tag));
  }

  Future<Color?> _pickNewTagColor(String name) {
    var selectedColor = tagDefaultColor;
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Color de "$name"'),
              content: _TagColorPicker(
                selected: selectedColor,
                onChanged: (color) =>
                    setDialogState(() => selectedColor = color),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedColor),
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    await _commitInlineEditing();
    if (!mounted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final db = _db;
    if (db == null) return;
    final account = _selectedAccount;
    if (account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una cuenta')));
      return;
    }
    if (_isMockAccount(account)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La cuenta creada desde el formulario aun no se puede guardar',
          ),
        ),
      );
      return;
    }
    final category = _selectedCategory;
    if (category == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una categoria')));
      return;
    }
    if (_isMockCategory(category)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La categoria creada desde el formulario aun no se puede guardar',
          ),
        ),
      );
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
      if (_isMockAccount(destinationAccount)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La cuenta destino creada desde el formulario aun no se puede guardar',
            ),
          ),
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
      await createManualTransaction(
        db,
        ManualTransactionInput(
          kind: switch (_type) {
            TransactionFormType.income => ManualTransactionKind.income,
            TransactionFormType.expense => ManualTransactionKind.expense,
            TransactionFormType.transfer => ManualTransactionKind.transfer,
          },
          name: _type == TransactionFormType.transfer
              ? 'Transferencia'
              : _titleController.text.trim(),
          description: _emptyToNull(_descriptionController.text),
          date: _selectedDate,
          accountId: account.id,
          categoryId: category.id,
          amount: amount,
          destinationAccountId: destinationAccount?.id,
          destinationAmount: destinationAmount,
          exchangeRate: exchangeRate,
          tags: _tags
              .map(
                (tag) => LocalTagDraft(
                  id: tag.id,
                  name: tag.name,
                  colorHex: colorToHex(tag.color),
                ),
              )
              .toList(growable: false),
        ),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Movimiento anotado')),
      );
      navigator.pop();
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

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF8F8),
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
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
                  key: ValueKey(_type),
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
                          Row(
                            children: [
                              Expanded(
                                child: _PickerChip(
                                  label:
                                      _selectedAccount?.name ?? 'Seleccionar',
                                  onPressed: _isSaving
                                      ? null
                                      : () => _pickAccount(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: _isSaving
                                    ? null
                                    : () => unawaited(
                                        _createMockAccountFromButton(),
                                      ),
                                icon: const Icon(Icons.add_rounded),
                                tooltip: 'Nueva cuenta',
                              ),
                            ],
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
                  key: ValueKey('amount-${_type.name}'),
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
              Row(
                children: [
                  const Expanded(child: _SectionLabel('Categoria')),
                  IconButton.outlined(
                    onPressed: _isSaving
                        ? null
                        : () => unawaited(_createMockCategoryFromButton()),
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Nueva categoria',
                  ),
                ],
              ),
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
                  prefixIcon: IconButton(
                    tooltip: 'Elegir etiqueta existente',
                    onPressed: _isSaving ? null : _pickExistingTag,
                    icon: const Icon(Icons.sell_rounded),
                  ),
                  suffixIcon: IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => unawaited(_addTag(_tagController.text)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                onFieldSubmitted: (value) => unawaited(_addTag(value)),
                onChanged: (value) {
                  if (value.endsWith(',')) {
                    unawaited(_addTag(value.substring(0, value.length - 1)));
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
                        label: Text(tag.name),
                        backgroundColor: tag.color,
                        side: BorderSide(color: tag.color),
                        onDeleted: _isSaving
                            ? null
                            : () => setState(() => _tags.remove(tag)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
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
            ],
          ),
        ),
      ),
    );
  }

  void _changeType(TransactionFormType type) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _type = type;
      _replaceEditableControllers();
      _selectedCategory = _resolveSelectedCategory(
        current: null,
        categories: _categoryOptions,
        type: type,
      );
      _tags.clear();
      _isRecurringExpense = false;
      _sourceAmountTouched = false;
      _destinationAmountTouched = false;
    });
  }

  void _replaceEditableControllers() {
    final oldAmountController = _amountController;
    final oldDestinationAmountController = _destinationAmountController;
    final oldTitleController = _titleController;
    final oldDescriptionController = _descriptionController;
    final oldTagController = _tagController;

    _amountController = TextEditingController();
    _destinationAmountController = TextEditingController();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _tagController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldAmountController.dispose();
      oldDestinationAmountController.dispose();
      oldTitleController.dispose();
      oldDescriptionController.dispose();
      oldTagController.dispose();
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

  bool _isMockAccount(Account account) =>
      account.id.startsWith('mock:account:');

  bool _isMockCategory(Category category) =>
      category.id.startsWith('mock:category:');

  Future<Account?> _createMockAccountDialog() async {
    final controller = TextEditingController();
    String currency = _mockCurrencyOptions.first;
    final result = await showDialog<Account>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nueva cuenta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      final created = _buildMockAccount(
                        controller.text.trim(),
                        currency,
                      );
                      if (created != null) Navigator.pop(context, created);
                    },
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: 'Moneda'),
                    items: _mockCurrencyOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => currency = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    final created = _buildMockAccount(
                      controller.text.trim(),
                      currency,
                    );
                    if (created != null) Navigator.pop(context, created);
                  },
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  Future<Category?> _createMockCategoryDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<Category>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nueva categoria'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              final created = _buildMockCategory(controller.text.trim());
              if (created != null) Navigator.pop(context, created);
            },
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final created = _buildMockCategory(controller.text.trim());
                if (created != null) Navigator.pop(context, created);
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Account? _buildMockAccount(String name, String currency) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final normalizedName = _normalizeIdentity(trimmed);
    final exists = _accountOptions.any(
      (account) =>
          _normalizeIdentity(account.name) == normalizedName &&
          account.currency == currency,
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya existe una cuenta con ese nombre y moneda'),
        ),
      );
      return null;
    }
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final account = Account(
      id: 'mock:account:$now',
      name: trimmed,
      currency: currency,
      description: null,
      color: null,
      icon: null,
      archived: false,
      createdAt: now,
      updatedAt: now,
      dirty: false,
    );
    setState(() {
      _mockAccounts.add(account);
      _selectedAccount = account;
      if (_type == TransactionFormType.transfer &&
          _selectedDestinationAccount == null) {
        _selectedDestinationAccount = _resolveDestinationAccount(
          current: null,
          accounts: _accountOptions,
          source: account,
        );
      }
    });
    return account;
  }

  Category? _buildMockCategory(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final normalizedName = _normalizeIdentity(trimmed);
    final exists = _categoryOptions.any(
      (category) => _normalizeIdentity(category.name) == normalizedName,
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya existe una categoria con ese nombre')),
      );
      return null;
    }
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final category = Category(
      id: 'mock:category:$now',
      name: trimmed,
      description: null,
      archived: false,
      createdAt: now,
      updatedAt: now,
      dirty: false,
    );
    setState(() {
      _mockCategories.add(category);
      _selectedCategory = category;
    });
    return category;
  }

  Future<void> _createMockAccountFromButton() async {
    final created = await _createMockAccountDialog();
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cuenta agregada al formulario')),
    );
  }

  Future<void> _createMockCategoryFromButton() async {
    final created = await _createMockCategoryDialog();
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Categoria agregada al formulario')),
    );
  }
}

const _mockCurrencyOptions = ['ARS', 'USD', 'EUR', 'BRL'];

String _normalizeIdentity(String value) => value.trim().toLowerCase();

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
    super.key,
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

  final Account? sourceAccount;
  final Account? destinationAccount;
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
  final Account? account;
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
          key: ValueKey('transfer-$label'),
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w600,
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
    super.key,
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
        suffixIcon: IconButton(
          onPressed: enabled ? () => _setAmountToZero(controller) : null,
          icon: const Icon(Icons.cancel_outlined),
        ),
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

class _TagColorPicker extends StatelessWidget {
  const _TagColorPicker({required this.selected, required this.onChanged});

  final Color selected;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final color in tagColorOptions)
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onChanged(color),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: color == selected
                  ? const Icon(Icons.check_rounded, size: 20)
                  : null,
            ),
          ),
      ],
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

class _FormTag {
  const _FormTag({this.id, required this.name, required this.color});

  final String? id;
  final String name;
  final Color color;
}

double? _parseAmount(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.'));
}

void _setAmountToZero(TextEditingController controller) {
  controller.value = const TextEditingValue(
    text: '0',
    selection: TextSelection.collapsed(offset: 1),
  );
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
