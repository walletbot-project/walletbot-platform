import 'package:app/components/account_icons.dart';
import 'package:app/components/category_icons.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/readable_time_picker.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

enum TransactionDetailTransferSide { source, destination }

class TransactionDetailsScreen extends StatefulWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.transactionId,
    required this.repos,
    this.transferSide,
  });

  final String transactionId;
  final AppRepositories repos;
  final TransactionDetailTransferSide? transferSide;

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  Transaction? _transaction;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  List<Tag> _tags = const [];
  Set<String> _selectedTagIds = const {};
  Account? _selectedAccount;
  Account? _selectedDestinationAccount;
  Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  bool _selectedDateConfirmed = true;
  TransactionTimeStatus _selectedTimeStatus = TransactionTimeStatus.none;
  Map<String, AccountBalanceAroundTransaction?> _balances = const {};

  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.repos.transactions.getById(widget.transactionId),
      widget.repos.accounts.listAll(includeArchived: true),
      widget.repos.categories.listAll(includeArchived: true),
      widget.repos.tags.listAll(includeArchived: true),
      widget.repos.transactions.tagIdsOf(widget.transactionId),
    ]);
    if (!mounted) return;

    final transaction = results[0] as Transaction?;
    final accounts = List<Account>.from(results[1] as List<Account>);
    final categories = List<Category>.from(results[2] as List<Category>);
    final tags = List<Tag>.from(results[3] as List<Tag>);
    final tagIds = Set<String>.from(results[4] as List<String>);

    categories.sort((a, b) => a.name.compareTo(b.name));
    tags.sort((a, b) => a.name.compareTo(b.name));

    _transaction = transaction;
    _accounts = accounts;
    _categories = categories;
    _tags = tags;
    _selectedTagIds = tagIds;
    if (transaction != null) {
      _nameController.text = transaction.name;
      _descriptionController.text = transaction.description ?? '';
      _amountController.text = _formatAmountInput(
        _amountFieldValue(transaction),
      );
      _selectedDate = DateTime.fromMillisecondsSinceEpoch(
        transaction.date.toInt(),
      );
      _selectedDateConfirmed = transaction.dateConfirmed;
      _selectedTimeStatus = transaction.timeStatus;
      _selectedAccount = accounts
          .where((account) => account.id == transaction.accountId)
          .firstOrNull;
      _selectedDestinationAccount = transaction.toAccountId == null
          ? null
          : accounts
                .where((account) => account.id == transaction.toAccountId)
                .firstOrNull;
      _selectedCategory = categories
          .where((category) => category.id == transaction.categoryId)
          .firstOrNull;
    } else {
      _selectedAccount = null;
      _selectedDestinationAccount = null;
      _selectedCategory = null;
    }

    _balances = await _loadBalances(transaction);
    if (!mounted) return;

    setState(() => _loading = false);
  }

  Future<Map<String, AccountBalanceAroundTransaction?>> _loadBalances(
    Transaction? transaction,
  ) async {
    if (transaction == null) return const {};
    final accountIds = <String>{
      if (_selectedAccount != null) _selectedAccount!.id,
      if (transaction.type == 'transfer' && _selectedDestinationAccount != null)
        _selectedDestinationAccount!.id,
    };
    final entries = await Future.wait(
      accountIds.map((accountId) async {
        final balance = await widget.repos.transactions
            .balanceAroundTransaction(
              transactionId: transaction.id,
              accountId: accountId,
            );
        return MapEntry(accountId, balance);
      }),
    );
    return Map.fromEntries(entries);
  }

  Account? get _account {
    final transaction = _transaction;
    if (transaction == null) return null;
    return _selectedAccount;
  }

  Account? get _destinationAccount {
    final transaction = _transaction;
    if (transaction?.type != 'transfer') return null;
    return _selectedDestinationAccount;
  }

  List<Tag> get _selectedTags => [
    for (final tag in _tags)
      if (_selectedTagIds.contains(tag.id)) tag,
  ];

  List<Tag> get _availableTags => [
    for (final tag in _tags)
      if (!tag.archived && !_selectedTagIds.contains(tag.id)) tag,
  ];

  bool get _canEditAmount {
    final type = _transaction?.type;
    return type == 'income' || type == 'expense' || type == 'transfer';
  }

  bool get _canEditAccount {
    return _transaction?.type != 'balance_adjustment';
  }

  Future<void> _toggleEditing() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    final transaction = _transaction;
    if (transaction == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('El nombre no puede estar vacío');
      return;
    }

    final selectedAccount = _selectedAccount;
    if (selectedAccount == null) {
      _showSnack('Elegí una cuenta');
      return;
    }

    Account? selectedDestinationAccount;
    if (transaction.type == 'transfer') {
      selectedDestinationAccount = _selectedDestinationAccount;
      if (selectedDestinationAccount == null) {
        _showSnack('Elegí una cuenta destino');
        return;
      }
      if (selectedDestinationAccount.id == selectedAccount.id) {
        _showSnack('La cuenta origen y destino deben ser distintas');
        return;
      }
    }

    BigInt? parsedAmount;
    if (_canEditAmount) {
      final parsed = double.tryParse(
        _amountController.text.trim().replaceAll(',', '.'),
      );
      if (parsed == null) {
        _showSnack('El monto no es válido');
        return;
      }
      parsedAmount = BigInt.from((parsed.abs() * 100).round());
    }

    var amount = const Value<BigInt>.absent();
    var toAmount = const Value<BigInt?>.absent();
    var exchangeRate = const Value<double?>.absent();
    if (parsedAmount != null) {
      if (transaction.type == 'transfer') {
        final destinationSide =
            widget.transferSide == TransactionDetailTransferSide.destination;
        final sameCurrency =
            selectedDestinationAccount!.currency == selectedAccount.currency;
        if (destinationSide) {
          toAmount = Value<BigInt?>(parsedAmount);
          if (sameCurrency) {
            amount = Value(parsedAmount);
          }
        } else {
          amount = Value(parsedAmount);
          if (sameCurrency) {
            toAmount = Value<BigInt?>(parsedAmount);
          }
        }

        final sourceAmount = amount.present ? amount.value : transaction.amount;
        final destinationAmount = toAmount.present
            ? toAmount.value ?? transaction.toAmount ?? transaction.amount
            : transaction.toAmount ?? transaction.amount;
        exchangeRate = sameCurrency || sourceAmount == BigInt.zero
            ? const Value<double?>(null)
            : Value<double?>(
                destinationAmount.toDouble() / sourceAmount.toDouble(),
              );
      } else {
        amount = Value(parsedAmount);
      }
    }

    setState(() => _saving = true);
    try {
      final originalDate = DateTime.fromMillisecondsSinceEpoch(
        transaction.date.toInt(),
      );
      final dateChanged =
          originalDate.millisecondsSinceEpoch !=
          _selectedDate.millisecondsSinceEpoch;
      final dateStatusChanged =
          _selectedDateConfirmed != transaction.dateConfirmed;
      final timeStatusChanged = _selectedTimeStatus != transaction.timeStatus;
      await widget.repos.transactions.update(
        transaction.id,
        name: Value(name),
        description: Value(_emptyToNull(_descriptionController.text)),
        date: dateChanged
            ? Value(BigInt.from(_selectedDate.millisecondsSinceEpoch))
            : const Value.absent(),
        dateConfirmed: dateStatusChanged
            ? Value(_selectedDateConfirmed)
            : const Value.absent(),
        timeStatus: timeStatusChanged || dateChanged
            ? Value(_selectedTimeStatus)
            : const Value.absent(),
        accountId: Value(selectedAccount.id),
        currency: Value(selectedAccount.currency),
        amount: amount,
        toAccountId: transaction.type == 'transfer'
            ? Value(selectedDestinationAccount!.id)
            : const Value.absent(),
        toAmount: toAmount,
        toCurrency: transaction.type == 'transfer'
            ? Value(selectedDestinationAccount!.currency)
            : const Value.absent(),
        exchangeRate: exchangeRate,
        categoryId: _selectedCategory == null
            ? const Value.absent()
            : Value(_selectedCategory!.id),
      );

      final currentTagIds = (await widget.repos.transactions.tagIdsOf(
        transaction.id,
      )).toSet();
      final toAdd = _selectedTagIds.difference(currentTagIds).toList();
      final toRemove = currentTagIds.difference(_selectedTagIds).toList();
      if (toAdd.isNotEmpty) {
        await widget.repos.transactions.addTags(transaction.id, toAdd);
      }
      if (toRemove.isNotEmpty) {
        await widget.repos.transactions.removeTags(transaction.id, toRemove);
      }

      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Error updating transaction: $error\n$stackTrace');
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('No se pudo guardar la actividad');
      }
    }
  }

  Future<void> _confirmDelete() async {
    final transaction = _transaction;
    if (transaction == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Eliminar actividad'),
          content: Text('¿Seguro que querés eliminar "${transaction.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repos.transactions.delete(transaction.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Error deleting transaction: $error\n$stackTrace');
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('No se pudo eliminar la actividad');
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.accept,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selectedDate.hour,
        _selectedDate.minute,
      );
      _selectedDateConfirmed = true;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showReadableTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        picked.hour,
        picked.minute,
      );
      _selectedTimeStatus = TransactionTimeStatus.confirmed;
    });
  }

  Future<void> _pickAccount({required bool destination}) async {
    final otherAccountId = destination
        ? _selectedAccount?.id
        : _selectedDestinationAccount?.id;
    final availableAccounts = [
      for (final account in _accounts)
        if (!account.archived && account.id != otherAccountId) account,
    ];
    if (availableAccounts.isEmpty) {
      _showSnack('No hay otra cuenta disponible');
      return;
    }

    final currentAccount = destination
        ? _selectedDestinationAccount
        : _selectedAccount;
    final picked = await showModalBottomSheet<Account>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final account in availableAccounts)
                ListTile(
                  leading: _EntityCircleIcon(
                    icon: accountIconFromName(account.icon),
                    color: colorFromHex(
                      account.color,
                      fallback: accountDefaultColor,
                    ),
                  ),
                  title: Text(account.name),
                  subtitle: Text(account.currency),
                  trailing: account.id == currentAccount?.id
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(account),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (destination) {
        _selectedDestinationAccount = picked;
      } else {
        _selectedAccount = picked;
      }
    });
    await _loadBalanceFor(picked.id);
  }

  Future<void> _loadBalanceFor(String accountId) async {
    if (_balances.containsKey(accountId)) return;
    final transaction = _transaction;
    if (transaction == null) return;
    final balance = await widget.repos.transactions.balanceAroundTransaction(
      transactionId: transaction.id,
      accountId: accountId,
    );
    if (!mounted) return;
    setState(() => _balances = {..._balances, accountId: balance});
  }

  Future<void> _pickCategory() async {
    final activeCategories = [
      for (final category in _categories)
        if (!category.archived) category,
    ];
    if (activeCategories.isEmpty) return;
    final picked = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final category in activeCategories)
                ListTile(
                  leading: Icon(categoryIconFromName(category.icon)),
                  title: Text(category.name),
                  trailing: category.id == _selectedCategory?.id
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(category),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedCategory = picked);
  }

  Future<void> _pickTag() async {
    final available = _availableTags;
    final picked = await showModalBottomSheet<Tag>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (available.isEmpty)
                const ListTile(title: Text('No hay etiquetas disponibles')),
              for (final tag in available)
                ListTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: colorFromHex(tag.color),
                  ),
                  title: Text(tag.name),
                  onTap: () => Navigator.of(context).pop(tag),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTagIds = {..._selectedTagIds, picked.id});
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;
    final title = _editing ? 'Editar actividad' : 'Detalle';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: _editing ? 'Guardar' : 'Editar',
              onPressed: _loading || transaction == null
                  ? null
                  : _toggleEditing,
              icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
            ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _loading || transaction == null || _saving
                ? null
                : _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final transaction = _transaction;
    if (transaction == null) {
      return const Center(child: Text('La actividad ya no existe'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [_buildReceipt(context, transaction)],
    );
  }

  /// Single "comprobante"-style card: a header with the category icon, name and
  /// amount, a perforated separator, and a stack of label/value receipt rows.
  Widget _buildReceipt(BuildContext context, Transaction transaction) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final signedAmount = _signedAmountCents(transaction);
    final displayCurrency = _displayCurrency(transaction);
    final category = _selectedCategory;
    final categoryColor = category == null
        ? colors.onSurfaceVariant
        : colorFromHex(category.color, fallback: categoryDefaultColor);
    final categoryIcon = category == null
        ? Icons.receipt_long_rounded
        : categoryIconFromName(category.icon);
    final timeNeedsAttention =
        _selectedTimeStatus != TransactionTimeStatus.confirmed;
    final description = transaction.description;

    final rows = <Widget>[
      _ReceiptRow(
        icon: Icons.notes_rounded,
        label: 'Descripción',
        stacked: true,
        value: _editing
            ? TextField(
                controller: _descriptionController,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Sin descripción',
                ),
              )
            : Text(
                description == null || description.isEmpty
                    ? 'Sin descripción'
                    : description,
                style: description == null || description.isEmpty
                    ? TextStyle(color: colors.onSurfaceVariant)
                    : null,
              ),
      ),
      _ReceiptRow(
        icon: _selectedDateConfirmed
            ? Icons.calendar_month_rounded
            : Icons.help_outline_rounded,
        attention: !_selectedDateConfirmed,
        label: _selectedDateConfirmed ? 'Fecha' : 'Fecha estimada',
        trailing: _editing
            ? TextButton(onPressed: _pickDate, child: const Text('Cambiar'))
            : null,
        value: Text(_formatDate(_selectedDate)),
      ),
      _ReceiptRow(
        icon: timeNeedsAttention
            ? Icons.help_outline_rounded
            : Icons.schedule_outlined,
        attention: timeNeedsAttention,
        label: timeNeedsAttention ? 'Horario estimado' : 'Horario',
        trailing: _editing
            ? TextButton(onPressed: _pickTime, child: const Text('Cambiar'))
            : null,
        value: Text(_formatTime(context, _selectedDate)),
      ),
      if (_account != null)
        _accountReceiptRow(
          label: transaction.type == 'transfer' ? 'Cuenta origen' : 'Cuenta',
          account: _account!,
          balance: _balances[_account!.id],
          trailing: _editing && _canEditAccount
              ? TextButton(
                  onPressed: () => _pickAccount(destination: false),
                  child: const Text('Cambiar'),
                )
              : null,
        ),
      if (_destinationAccount != null)
        _accountReceiptRow(
          label: 'Cuenta destino',
          account: _destinationAccount!,
          balance: _balances[_destinationAccount!.id],
          trailing: _editing && _canEditAccount
              ? TextButton(
                  onPressed: () => _pickAccount(destination: true),
                  child: const Text('Cambiar'),
                )
              : null,
        ),
      _ReceiptRow(
        icon: categoryIcon,
        iconColor: category == null ? null : categoryColor,
        label: 'Categoría',
        trailing: _editing
            ? TextButton(
                onPressed: _categories.any((category) => !category.archived)
                    ? _pickCategory
                    : null,
                child: const Text('Cambiar'),
              )
            : null,
        value: Text(
          category?.name ?? 'Sin categoría',
          style: category == null
              ? TextStyle(color: colors.onSurfaceVariant)
              : null,
        ),
      ),
      _tagsReceiptRow(),
    ];

    return Material(
      color: colors.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(kGroupOuterRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(categoryIcon, size: 30, color: categoryColor),
              ),
            ),
            const SizedBox(height: 16),
            if (_editing)
              TextField(
                controller: _nameController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.sentences,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: 'Nombre',
                  border: InputBorder.none,
                ),
              )
            else
              Text(
                transaction.name,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            if (_editing && _canEditAmount)
              TextField(
                controller: _amountController,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  prefixText: currencyPrefix(_amountFieldCurrency(transaction)),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              Text(
                formatMoney(signedAmount, displayCurrency),
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  color: signedAmount > 0
                      ? Colors.green.shade600
                      : colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (!_canEditAmount && _editing) ...[
              const SizedBox(height: 8),
              Text(
                'El monto de ajustes de saldo y balances iniciales no son editables.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const _ReceiptDivider(),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colors.outlineVariant),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  _ReceiptRow _accountReceiptRow({
    required String label,
    required Account account,
    required AccountBalanceAroundTransaction? balance,
    Widget? trailing,
  }) {
    final color = colorFromHex(account.color, fallback: accountDefaultColor);
    return _ReceiptRow(
      icon: accountIconFromName(account.icon),
      iconColor: color,
      label: label,
      trailing: trailing,
      stacked: true,
      value: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.name),
              const SizedBox(height: 4),
              if (balance == null)
                Text(
                  'Saldo no disponible',
                  style: TextStyle(color: colors.onSurfaceVariant),
                )
              else
                Text(
                  'Antes: ${formatMoney(balance.before.toInt(), account.currency)}'
                  '  ·  Después: ${formatMoney(balance.after.toInt(), account.currency)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  _ReceiptRow _tagsReceiptRow() {
    final selectedTags = _selectedTags;
    return _ReceiptRow(
      icon: Icons.sell_outlined,
      label: 'Tags',
      stacked: true,
      trailing: _editing
          ? TextButton(onPressed: _pickTag, child: const Text('Agregar'))
          : null,
      value: selectedTags.isEmpty
          ? Builder(
              builder: (context) => Text(
                'Sin tags',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in selectedTags)
                  if (_editing)
                    InputChip(
                      avatar: const CircleAvatar(backgroundColor: Colors.white),
                      label: Text(tag.name),
                      backgroundColor: colorFromHex(tag.color),
                      onDeleted: () => setState(
                        () =>
                            _selectedTagIds = {..._selectedTagIds}
                              ..remove(tag.id),
                      ),
                    )
                  else
                    Chip(
                      avatar: const CircleAvatar(backgroundColor: Colors.white),
                      label: Text(tag.name),
                      backgroundColor: colorFromHex(tag.color),
                    ),
              ],
            ),
    );
  }

  int _signedAmountCents(Transaction t) {
    final amount = t.amount.toInt();
    switch (t.type) {
      case 'expense':
        return -amount.abs();
      case 'income':
        return amount.abs();
      case 'transfer':
        return switch (widget.transferSide) {
          TransactionDetailTransferSide.source => -amount.abs(),
          TransactionDetailTransferSide.destination =>
            (t.toAmount ?? t.amount).toInt().abs(),
          null => amount.abs(),
        };
      case 'balance_adjustment':
        return amount;
      default:
        return amount;
    }
  }

  String _displayCurrency(Transaction t) {
    if (t.type == 'transfer' &&
        widget.transferSide == TransactionDetailTransferSide.destination) {
      return t.toCurrency ?? t.currency;
    }
    return t.currency;
  }

  BigInt _amountFieldValue(Transaction t) {
    if (t.type == 'transfer' &&
        widget.transferSide == TransactionDetailTransferSide.destination) {
      return t.toAmount ?? t.amount;
    }
    return t.amount;
  }

  String _amountFieldCurrency(Transaction t) {
    if (t.type == 'transfer' &&
        widget.transferSide == TransactionDetailTransferSide.destination) {
      return _selectedDestinationAccount?.currency ??
          t.toCurrency ??
          t.currency;
    }
    return _selectedAccount?.currency ?? t.currency;
  }

  String _formatAmountInput(BigInt amount) {
    return (amount.abs().toInt() / 100).toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(date));

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A perforated separator that gives the card its "comprobante" feel.
class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DashedLinePainter(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A single line item inside the receipt card: a leading icon and label on the
/// left, its value on the right (or stacked below for longer content).
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.trailing,
    this.stacked = false,
    this.attention = false,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final Color? iconColor;
  final Widget? trailing;
  final bool stacked;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final labelColor = attention
        ? Colors.orange.shade800
        : colors.onSurfaceVariant;
    final resolvedIconColor = iconColor ?? labelColor;

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: resolvedIconColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: textTheme.labelLarge?.copyWith(color: labelColor),
          ),
        ),
      ],
    );

    final styledValue = DefaultTextStyle.merge(
      style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
      child: value,
    );

    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: labelRow),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            styledValue,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          labelRow,
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.end,
                style: textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                child: value,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _EntityCircleIcon extends StatelessWidget {
  const _EntityCircleIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
