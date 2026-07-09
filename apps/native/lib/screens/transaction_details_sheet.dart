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

class TransactionDetailsSheet extends StatefulWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transactionId,
    required this.repos,
  });

  final String transactionId;
  final AppRepositories repos;

  @override
  State<TransactionDetailsSheet> createState() =>
      _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState extends State<TransactionDetailsSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  Transaction? _transaction;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  List<Tag> _tags = const [];
  Set<String> _selectedTagIds = const {};
  Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();

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
      _amountController.text = _formatAmountInput(transaction.amount);
      _selectedDate = DateTime.fromMillisecondsSinceEpoch(
        transaction.date.toInt(),
      );
      _selectedCategory = categories
          .where((category) => category.id == transaction.categoryId)
          .firstOrNull;
    }
    setState(() => _loading = false);
  }

  Account? get _account {
    final transaction = _transaction;
    if (transaction == null) return null;
    return _accounts
        .where((account) => account.id == transaction.accountId)
        .firstOrNull;
  }

  Account? get _destinationAccount {
    final transaction = _transaction;
    if (transaction?.toAccountId == null) return null;
    return _accounts
        .where((account) => account.id == transaction!.toAccountId)
        .firstOrNull;
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
    return type == 'income' || type == 'expense';
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

    BigInt? amount;
    if (_canEditAmount) {
      final parsed = double.tryParse(
        _amountController.text.trim().replaceAll(',', '.'),
      );
      if (parsed == null) {
        _showSnack('El monto no es válido');
        return;
      }
      amount = BigInt.from((parsed.abs() * 100).round());
    }

    setState(() => _saving = true);
    try {
      await widget.repos.transactions.update(
        transaction.id,
        name: Value(name),
        description: Value(_emptyToNull(_descriptionController.text)),
        date: Value(BigInt.from(_selectedDate.millisecondsSinceEpoch)),
        amount: amount == null ? const Value.absent() : Value(amount),
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
    if (_loading) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final transaction = _transaction;
    if (transaction == null) {
      return const SizedBox(
        height: 260,
        child: Center(child: Text('La actividad ya no existe')),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _buildHero(context, transaction),
            const SizedBox(height: 12),
            _buildActions(context),
            const SizedBox(height: 20),
            _buildDetails(context, transaction),
          ],
        );
      },
    );
  }

  Widget _buildHero(BuildContext context, Transaction transaction) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final signedAmount = _signedAmountCents(transaction);

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
                  prefixText: currencyPrefix(transaction.currency),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              Text(
                formatMoney(signedAmount, transaction.currency),
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
                'El monto de transferencias y ajustes se edita desde el flujo dedicado.',
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

  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _toggleEditing,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined),
            label: Text(_editing ? 'Listo' : 'Editar'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _saving ? null : _confirmDelete,
          style: IconButton.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          tooltip: 'Eliminar',
          icon: const Icon(Icons.delete_outline),
        ),
      ],
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
          iconColor: time.isEstimatedAtLoad ? attentionColor : null,
          backgroundColor: time.isTentativeRange || time.isEstimatedAtLoad
              ? attentionBackground
              : null,
          label: time.isEstimatedAtLoad
              ? 'Horario estimado'
              : 'Rango horario tentativo',
          child: Text(
            time.isEstimatedAtLoad
                ? '${formatMockTransactionHour(time.hour)} · asumido al momento de carga'
                : '${time.rangeLabel} · ${time.rangeText}',
          ),
        ),
        const SizedBox(height: 12),
        if (_account != null)
          _AccountDetailCard(
            label: transaction.type == 'transfer' ? 'Cuenta origen' : 'Cuenta',
            account: _account!,
            transactionId: transaction.id,
            repos: widget.repos,
          ),
        if (_destinationAccount != null) ...[
          const SizedBox(height: kGroupSpacing),
          _AccountDetailCard(
            label: 'Cuenta destino',
            account: _destinationAccount!,
            transactionId: transaction.id,
            repos: widget.repos,
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
    return _DetailCard(
      icon: category == null
          ? Icons.category_outlined
          : categoryIconFromName(category.icon),
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
      case 'transfer':
        return amount.abs();
      case 'balance_adjustment':
        return amount;
      default:
        return amount;
    }
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
    required this.transactionId,
    required this.repos,
  });

  final String label;
  final Account account;
  final String transactionId;
  final AppRepositories repos;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(account.color, fallback: accountDefaultColor);
    return _DetailCard(
      icon: accountIconFromName(account.icon),
      iconColor: color,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.name),
          const SizedBox(height: 8),
          FutureBuilder<AccountBalanceAroundTransaction?>(
            future: repos.transactions.balanceAroundTransaction(
              transactionId: transactionId,
              accountId: account.id,
            ),
            builder: (context, snapshot) {
              final balance = snapshot.data;
              if (balance == null) {
                return Text(
                  'Saldo no disponible',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Wrap(
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
              );
            },
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
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Color? backgroundColor;
  final Color? iconColor;
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
            Icon(icon, color: iconColor ?? colors.onSurfaceVariant),
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
