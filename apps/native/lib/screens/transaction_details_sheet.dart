import 'package:app/components/account_icons.dart';
import 'package:app/components/category_icons.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/components/transaction_time_mock.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
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
      await widget.repos.transactions.update(
        transaction.id,
        name: Value(name),
        description: Value(_emptyToNull(_descriptionController.text)),
        date: Value(BigInt.from(_selectedDate.millisecondsSinceEpoch)),
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
      children: [
        _buildHero(context, transaction),
        const SizedBox(height: 20),
        _buildDetails(context, transaction),
      ],
    );
  }

  Widget _buildHero(BuildContext context, Transaction transaction) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final signedAmount = _signedAmountCents(transaction);
    final displayCurrency = _displayCurrency(transaction);

    return GroupedCard(
      borderRadius: BorderRadius.circular(kGroupOuterRadius),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editing)
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Text(
                transaction.name,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 12),
            if (_editing && _canEditAmount)
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Monto',
                  prefixText: currencyPrefix(_amountFieldCurrency(transaction)),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              Text(
                formatMoney(signedAmount, displayCurrency),
                style: textTheme.displaySmall?.copyWith(
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
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Transaction transaction) {
    final colors = Theme.of(context).colorScheme;
    final time = mockTransactionTime(
      transactionId: transaction.id,
      createdAt: transaction.createdAt,
    );
    final attentionBackground = _attentionBackground(colors);
    final attentionColor = _attentionColor(colors);
    final description = transaction.description;
    return Column(
      children: [
        _DetailCard(
          icon: Icons.notes_rounded,
          label: 'Descripción',
          child: _editing
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
                ),
        ),
        const SizedBox(height: kGroupSpacing),
        _DetailCard(
          icon: transaction.dateConfirmed
              ? Icons.calendar_month_rounded
              : Icons.help_outline_rounded,
          iconColor: transaction.dateConfirmed ? null : attentionColor,
          backgroundColor: transaction.dateConfirmed
              ? null
              : attentionBackground,
          label: transaction.dateConfirmed ? 'Fecha' : 'Fecha estimada',
          trailing: _editing
              ? TextButton(onPressed: _pickDate, child: const Text('Cambiar'))
              : null,
          child: Text(
            transaction.dateConfirmed
                ? _formatDate(_selectedDate)
                : '${_formatDate(_selectedDate)} · asumida por carga',
          ),
        ),
        const SizedBox(height: kGroupSpacing),
        _DetailCard(
          icon: time.icon,
          iconColor: time.needsAttention ? attentionColor : null,
          backgroundColor: time.needsAttention ? attentionBackground : null,
          label: time.detailLabel,
          child: Text(time.detailText),
        ),
        const SizedBox(height: 12),
        if (_account != null)
          _AccountDetailCard(
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
        if (_destinationAccount != null) ...[
          const SizedBox(height: kGroupSpacing),
          _AccountDetailCard(
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
        ],
        const SizedBox(height: 12),
        _buildCategoryCard(),
        const SizedBox(height: kGroupSpacing),
        _buildTagsCard(),
      ],
    );
  }

  Widget _buildCategoryCard() {
    final category = _selectedCategory;
    final color = category == null
        ? null
        : colorFromHex(category.color, fallback: categoryDefaultColor);
    return _DetailCard(
      icon: category == null
          ? Icons.category_outlined
          : categoryIconFromName(category.icon),
      iconColor: color,
      iconBackgroundColor: color?.withValues(alpha: 0.16),
      label: 'Categoría',
      trailing: _editing
          ? TextButton(
              onPressed: _categories.any((category) => !category.archived)
                  ? _pickCategory
                  : null,
              child: const Text('Cambiar'),
            )
          : null,
      child: Text(category?.name ?? 'Sin categoría'),
    );
  }

  Widget _buildTagsCard() {
    final selectedTags = _selectedTags;
    return _DetailCard(
      icon: Icons.sell_outlined,
      label: 'Tags',
      trailing: _editing
          ? TextButton(onPressed: _pickTag, child: const Text('Agregar'))
          : null,
      child: selectedTags.isEmpty
          ? const Text('Sin tags')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in selectedTags)
                  InputChip(
                    label: Text(tag.name),
                    backgroundColor: colorFromHex(tag.color),
                    side: BorderSide(color: colorFromHex(tag.color)),
                    onDeleted: _editing
                        ? () => setState(
                            () =>
                                _selectedTagIds = {..._selectedTagIds}
                                  ..remove(tag.id),
                          )
                        : null,
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

  Color _attentionBackground(ColorScheme colors) {
    return Color.alphaBlend(
      Colors.orange.withValues(alpha: 0.18),
      colors.surfaceContainerHigh,
    );
  }

  Color _attentionColor(ColorScheme colors) {
    return Colors.orange.shade800;
  }
}

class _AccountDetailCard extends StatelessWidget {
  const _AccountDetailCard({
    required this.label,
    required this.account,
    required this.balance,
    this.trailing,
  });

  final String label;
  final Account account;
  final AccountBalanceAroundTransaction? balance;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(account.color, fallback: accountDefaultColor);
    final balance = this.balance;
    return _DetailCard(
      icon: accountIconFromName(account.icon),
      iconColor: color,
      iconBackgroundColor: color.withValues(alpha: 0.16),
      label: label,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.name),
          const SizedBox(height: 8),
          if (balance == null)
            Text(
              'Saldo no disponible',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'Antes: ${formatMoney(balance.before.toInt(), account.currency)}',
                ),
                Text(
                  'Después: ${formatMoney(balance.after.toInt(), account.currency)}',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.label,
    required this.child,
    this.backgroundColor,
    this.iconColor,
    this.iconBackgroundColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: backgroundColor ?? colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(kGroupOuterRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailIcon(
              icon: icon,
              color: iconColor ?? colors.onSurfaceVariant,
              backgroundColor: iconBackgroundColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: textTheme.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 6),
                  child,
                ],
              ),
            ),
          ],
        ),
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

class _DetailIcon extends StatelessWidget {
  const _DetailIcon({
    required this.icon,
    required this.color,
    this.backgroundColor,
  });

  final IconData icon;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = this.backgroundColor;
    if (backgroundColor == null) {
      return Icon(icon, color: color);
    }

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
