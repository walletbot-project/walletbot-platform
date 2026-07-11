import 'dart:async';

import 'package:app/components/color_utils.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
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

  TransactionFormType _type = TransactionFormType.income;
  AppRepositories? _repos;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
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
  String? _transferAccountError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = context.read<AppRepositories>();
    if (_repos == repos) return;
    _repos = repos;
    unawaited(_loadFormData(repos));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _destinationAmountController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData(AppRepositories repos) async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      repos.accounts.listActive(),
      repos.categories.listActive(),
      repos.tags.listActive(),
    ]);
    final accounts = List<Account>.from(results[0] as List<Account>)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final categories = List<Category>.from(results[1] as List<Category>)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final tags = List<Tag>.from(results[2] as List<Tag>)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
        accounts: accounts,
      );
      _selectedDestinationAccount = _resolveDestinationAccount(
        current: _selectedDestinationAccount,
        accounts: accounts,
        source: _selectedAccount,
      );
      _selectedCategory = _resolveSelectedCategory(
        current: _selectedCategory,
        categories: categories,
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
        final name = category.name.toLowerCase();
        if (name == context.l10n.transfer.toLowerCase() ||
            name == 'transferencia' ||
            name == 'transfer') {
          return category;
        }
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
                title: Text(context.l10n.newAccount),
                onTap: () async {
                  final created = await _createMockAccountDialog();
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                },
              ),
              for (final account in _accounts)
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
      _transferAccountError = null;
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
                title: Text(context.l10n.newCategory),
                onTap: () async {
                  final created = await _createMockCategoryDialog();
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                },
              ),
              for (final category in _categories)
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

  Future<_FormTag?> _createTag(String rawValue) async {
    final name = rawValue.trim();
    if (name.isEmpty) return null;
    final alreadySelected = _tags.any(
      (tag) => tag.name.toLowerCase() == name.toLowerCase(),
    );
    if (alreadySelected) {
      return null;
    }

    final existingTag = _findKnownTag(name);
    if (existingTag != null) {
      return existingTag;
    }

    final color = await _pickNewTagColor(name);
    if (color == null || !mounted) return null;
    final repos = _repos;
    if (repos == null) return null;
    try {
      final id = await repos.tags.create(name: name, color: colorToHex(color));
      if (!mounted) return null;
      final tag = _FormTag(id: id, name: name, color: color);
      setState(() => _knownTags = [..._knownTags, tag]);
      return tag;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tagCreateFailed(error))),
      );
      return null;
    }
  }

  Future<void> _commitInlineEditing() async {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  _FormTag? _findKnownTag(String name) {
    final normalized = name.toLowerCase();
    for (final tag in _knownTags) {
      if (tag.name.toLowerCase() == normalized) return tag;
    }
    return null;
  }

  Future<void> _pickTag() async {
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
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(context.l10n.newTag),
                onTap: () async {
                  final created = await _createMockTagDialog();
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                },
              ),
              if (availableTags.isEmpty)
                ListTile(title: Text(context.l10n.noTagsAvailable)),
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

  Future<_FormTag?> _createMockTagDialog() async {
    return showDialog<_FormTag>(
      context: context,
      builder: (context) => _CreateTagDialog(onCreate: _createTag),
    );
  }

  Future<Color?> _pickNewTagColor(String name) {
    var selectedColor = tagDefaultColor;
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.enter):
                    const ActivateIntent(),
                const SingleActivator(LogicalKeyboardKey.numpadEnter):
                    const ActivateIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<Intent>(
                    onInvoke: (intent) {
                      Navigator.pop(context, selectedColor);
                      return null;
                    },
                  ),
                },
                child: AlertDialog(
                  title: Text(context.l10n.colorFor(name)),
                  content: _TagColorPicker(
                    selected: selectedColor,
                    onChanged: (color) =>
                        setDialogState(() => selectedColor = color),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, selectedColor),
                      child: Text(context.l10n.create),
                    ),
                  ],
                ),
              ),
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
    final repos = _repos;
    if (repos == null) return;
    final account = _selectedAccount;
    if (account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.selectAccount)));
      return;
    }
    final category = _selectedCategory;
    if (category == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.selectCategory)));
      return;
    }
    final destinationAccount = _selectedDestinationAccount;
    if (_type == TransactionFormType.transfer) {
      if (destinationAccount == null) {
        setState(
          () => _transferAccountError = context.l10n.selectDestinationAccount,
        );
        return;
      }
      if (destinationAccount.id == account.id) {
        setState(
          () => _transferAccountError = context.l10n.differentTransferAccounts,
        );
        return;
      }
      if (_transferAccountError != null) {
        setState(() => _transferAccountError = null);
      }
    }

    setState(() => _isSaving = true);
    final navigator = Navigator.of(context);

    try {
      final amountValue = _parseAmount(_amountController.text)!;
      final amount = _amountToCents(amountValue);
      final destinationAmountValue = _type == TransactionFormType.transfer
          ? _parseAmount(_destinationAmountController.text)
          : null;
      final exchangeRate =
          _shouldShowExchangeRate &&
              destinationAmountValue != null &&
              destinationAmountValue > 0
          ? destinationAmountValue / amountValue
          : null;
      final dateMs = BigInt.from(_selectedDate.millisecondsSinceEpoch);
      final tagIds = _tags
          .map((tag) => tag.id)
          .whereType<String>()
          .toList(growable: false);
      switch (_type) {
        case TransactionFormType.income:
          await repos.transactions.addIncome(
            accountId: account.id,
            categoryId: category.id,
            name: _titleController.text.trim(),
            amountCents: amount,
            currency: account.currency,
            description: _emptyToNull(_descriptionController.text),
            dateMs: dateMs,
            tagIds: tagIds,
          );
        case TransactionFormType.expense:
          await repos.transactions.addExpense(
            accountId: account.id,
            categoryId: category.id,
            name: _titleController.text.trim(),
            amountCents: amount,
            currency: account.currency,
            description: _emptyToNull(_descriptionController.text),
            dateMs: dateMs,
            tagIds: tagIds,
          );
        case TransactionFormType.transfer:
          await repos.transactions.addTransfer(
            fromAccountId: account.id,
            toAccountId: destinationAccount!.id,
            name: context.l10n.transfer,
            amountCents: amount,
            currency: account.currency,
            toAmountCents: _amountToCents(
              destinationAmountValue ?? amountValue,
            ),
            toCurrency: destinationAccount.currency,
            exchangeRate: exchangeRate,
            categoryId: category.id,
            description: _emptyToNull(_descriptionController.text),
            dateMs: dateMs,
            tagIds: tagIds,
          );
      }

      if (!mounted) return;
      navigator.pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.recordFailed(error))));
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
                context.l10n.newTransaction,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: SegmentedButton<TransactionFormType>(
                  segments: [
                    ButtonSegment(
                      value: TransactionFormType.income,
                      label: Text(context.l10n.income),
                    ),
                    ButtonSegment(
                      value: TransactionFormType.expense,
                      label: Text(context.l10n.expense),
                    ),
                    ButtonSegment(
                      value: TransactionFormType.transfer,
                      label: Text(context.l10n.transfer),
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
                  accountErrorText: _transferAccountError,
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
                          _SectionLabel(context.l10n.account),
                          const SizedBox(height: 10),
                          _PickerChip(
                            label:
                                _selectedAccount?.name ?? context.l10n.select,
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
                label: context.l10n.date,
                value: _formatDate(context, _selectedDate),
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
                  label: context.l10n.amount,
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.l10n.title,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _isSaving ? null : _titleController.clear,
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return context.l10n.titleRequired;
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
                  labelText: context.l10n.description,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _isSaving ? null : _descriptionController.clear,
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _SectionLabel(context.l10n.category),
              const SizedBox(height: 10),
              _PickerChip(
                label: _selectedCategory?.name ?? context.l10n.select,
                onPressed: _isSaving ? null : _pickCategory,
              ),
              const SizedBox(height: 24),
              _SectionLabel(context.l10n.tags),
              const SizedBox(height: 10),
              _PickerChip(
                label: context.l10n.addTag,
                onPressed: _isSaving ? null : _pickTag,
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
                      label: Text(context.l10n.cancel),
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
                      label: Text(context.l10n.record),
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
        categories: _categories,
        type: type,
      );
      _tags.clear();
      _isRecurringExpense = false;
      _sourceAmountTouched = false;
      _destinationAmountTouched = false;
      _transferAccountError = null;
    });
  }

  void _replaceEditableControllers() {
    final oldAmountController = _amountController;
    final oldDestinationAmountController = _destinationAmountController;
    final oldTitleController = _titleController;
    final oldDescriptionController = _descriptionController;

    _amountController = TextEditingController();
    _destinationAmountController = TextEditingController();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldAmountController.dispose();
      oldDestinationAmountController.dispose();
      oldTitleController.dispose();
      oldDescriptionController.dispose();
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
      _transferAccountError = null;
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

  Future<Account?> _createMockAccountDialog() async {
    final controller = TextEditingController();
    String currency = _mockCurrencyOptions.first;
    bool saving = false;
    final result = await showDialog<Account>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.l10n.newAccount),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
                      if (saving) return;
                      setDialogState(() => saving = true);
                      final created = await _createRealAccount(
                        controller.text.trim(),
                        currency,
                      );
                      if (context.mounted) {
                        setDialogState(() => saving = false);
                      }
                      if (created != null && context.mounted) {
                        Navigator.pop(context, created);
                      }
                    },
                    decoration: InputDecoration(labelText: context.l10n.name),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    decoration: InputDecoration(
                      labelText: context.l10n.currency,
                    ),
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
                  child: Text(context.l10n.cancel),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          final created = await _createRealAccount(
                            controller.text.trim(),
                            currency,
                          );
                          if (context.mounted) {
                            setDialogState(() => saving = false);
                          }
                          if (created != null && context.mounted) {
                            Navigator.pop(context, created);
                          }
                        },
                  child: Text(context.l10n.create),
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
    bool saving = false;
    final result = await showDialog<Category>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(context.l10n.newCategory),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) async {
                if (saving) return;
                setDialogState(() => saving = true);
                final created = await _createRealCategory(
                  controller.text.trim(),
                );
                if (context.mounted) {
                  setDialogState(() => saving = false);
                }
                if (created != null && context.mounted) {
                  Navigator.pop(context, created);
                }
              },
              decoration: InputDecoration(labelText: context.l10n.name),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        final created = await _createRealCategory(
                          controller.text.trim(),
                        );
                        if (context.mounted) {
                          setDialogState(() => saving = false);
                        }
                        if (created != null && context.mounted) {
                          Navigator.pop(context, created);
                        }
                      },
                child: Text(context.l10n.create),
              ),
            ],
          ),
        );
      },
    );
    return result;
  }

  Future<Account?> _createRealAccount(String name, String currency) async {
    final repos = _repos;
    if (repos == null) return null;
    try {
      final accountId = await repos.accounts.create(
        name: name,
        currency: currency,
      );
      await _loadFormData(repos);
      if (!mounted) return null;
      final account = _accounts
          .where((item) => item.id == accountId)
          .firstOrNull;
      if (account == null) return null;
      setState(() {
        _selectedAccount = account;
        if (_type == TransactionFormType.transfer &&
            _selectedDestinationAccount == null) {
          _selectedDestinationAccount = _resolveDestinationAccount(
            current: null,
            accounts: _accounts,
            source: account,
          );
        }
      });
      return account;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.accountCreateFailed)));
      return null;
    }
  }

  Future<Category?> _createRealCategory(String name) async {
    final repos = _repos;
    if (repos == null) return null;
    try {
      final categoryId = await repos.categories.create(name: name);
      await _loadFormData(repos);
      if (!mounted) return null;
      final category = _categories
          .where((item) => item.id == categoryId)
          .firstOrNull;
      if (category == null) return null;
      setState(() => _selectedCategory = category);
      return category;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.categoryCreateFailed)),
      );
      return null;
    }
  }
}

const _mockCurrencyOptions = ['ARS', 'USD', 'EUR', 'BRL'];

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
            context.l10n.recurringExpense,
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
    required this.accountErrorText,
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
  final String? accountErrorText;
  final bool enabled;
  final VoidCallback onPickSource;
  final VoidCallback onPickDestination;
  final VoidCallback? onSwap;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDestinationAmountChanged;

  @override
  Widget build(BuildContext context) {
    final errorText = accountErrorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TransferSide(
                label: context.l10n.leaves,
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
                label: context.l10n.enters,
                account: destinationAccount,
                amountController: destinationAmountController,
                enabled: enabled,
                onPickAccount: onPickDestination,
                onAmountChanged: onDestinationAmountChanged,
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              errorText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
            if (text.isEmpty) return context.l10n.required;
            final amount = _parseAmount(text);
            if (amount == null || amount <= 0) {
              return context.l10n.greaterThanZero;
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: _PickerChip(
            label: account == null
                ? context.l10n.select
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
        if (text.isEmpty) return context.l10n.amountRequired;
        final amount = _parseAmount(text);
        if (amount == null || amount <= 0) {
          return context.l10n.amountGreaterThanZero;
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
        for (final color in colorOptions)
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

class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog({required this.onCreate});

  final Future<_FormTag?> Function(String name) onCreate;

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final created = await widget.onCreate(_controller.text);
    if (!mounted) return;
    if (created == null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.newTag),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.none,
        onSubmitted: (_) => unawaited(_submit()),
        decoration: InputDecoration(labelText: context.l10n.name),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: _saving ? null : () => unawaited(_submit()),
          child: Text(context.l10n.create),
        ),
      ],
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

BigInt _amountToCents(double amount) {
  return BigInt.from((amount * 100).round());
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

String _formatDate(BuildContext context, DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return context.l10n.today;
  }
  return formatNumericDate(date, context.localeName);
}
