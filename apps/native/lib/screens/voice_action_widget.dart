import 'package:app/components/account_icons.dart';
import 'package:app/components/category_icons.dart';
import 'package:app/components/color_picker.dart';
import 'package:app/components/color_utils.dart';
import 'package:app/components/icon_picker.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/money.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const previewableToolNames = <String>{
  'addExpense',
  'addIncome',
  'addTransfer',
  'addBalanceAdjustment',
  'createAccount',
  'updateAccount',
  'createCategory',
  'updateCategory',
  'createTag',
  'updateTag',
  'updateTransaction',
};

bool isPreviewableTool(String name) => previewableToolNames.contains(name);

class VoiceActionWidget extends StatelessWidget {
  const VoiceActionWidget({
    super.key,
    required this.toolName,
    required this.entityId,
  });

  final String toolName;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    return switch (toolName) {
      'createAccount' || 'updateAccount' => _AccountActionWidget(
        entityId: entityId,
        wasUpdated: toolName == 'updateAccount',
      ),
      'createCategory' || 'updateCategory' => _CategoryActionWidget(
        entityId: entityId,
        wasUpdated: toolName == 'updateCategory',
      ),
      'createTag' || 'updateTag' => _TagActionWidget(
        entityId: entityId,
        wasUpdated: toolName == 'updateTag',
      ),
      'addExpense' ||
      'addIncome' ||
      'addTransfer' ||
      'addBalanceAdjustment' ||
      'updateTransaction' => _TxnActionWidget(
        entityId: entityId,
        wasUpdated: toolName == 'updateTransaction',
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

// =============================================================================
// Transaction preview and editor
// =============================================================================

class _TxnActionWidget extends StatefulWidget {
  const _TxnActionWidget({required this.entityId, required this.wasUpdated});

  final String entityId;
  final bool wasUpdated;

  @override
  State<_TxnActionWidget> createState() => _TxnActionWidgetState();
}

class _TxnActionWidgetState extends State<_TxnActionWidget> {
  Transaction? _transaction;
  Account? _account;
  Account? _toAccount;
  List<Category> _categories = const [];
  bool _loading = true;
  bool _failed = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    final repos = context.read<AppRepositories>();
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final transaction = await repos.transactions.getById(widget.entityId);
      if (!mounted) return;
      if (transaction == null) {
        setState(() {
          _transaction = null;
          _loading = false;
        });
        return;
      }
      final account = await repos.accounts.getById(transaction.accountId);
      final toAccount = transaction.toAccountId == null
          ? null
          : await repos.accounts.getById(transaction.toAccountId!);
      final categories = await repos.categories.listActive();
      if (!mounted) return;
      setState(() {
        _transaction = transaction;
        _account = account;
        _toAccount = toAccount;
        _categories = categories;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Error loading voice transaction preview: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _openEdit() {
    final transaction = _transaction;
    if (transaction == null) return;
    final repos = context.read<AppRepositories>();
    _showActionEditSheet(
      context,
      _TxnEditSheet(
        repository: repos.transactions,
        transaction: transaction,
        categories: _categories,
        onSaved: (updated) {
          if (mounted) setState(() => _transaction = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    if (_failed) return _ActionErrorCard(onRetry: _load);
    final transaction = _transaction;
    if (transaction == null) return const SizedBox.shrink();

    final (icon, color, typeLabel) = _txnTypeConfig(transaction.type, context);
    final amountLabel =
        transaction.type == 'transfer' &&
            transaction.toAmount != null &&
            transaction.toCurrency != null
        ? '${_formatAmount(transaction.amount, transaction.currency, context.localeName)} → '
              '${_formatAmount(transaction.toAmount!, transaction.toCurrency!, context.localeName)}'
        : transaction.type == 'balance_adjustment' &&
              transaction.balanceAfter != null
        ? _formatAmount(
            transaction.balanceAfter!,
            transaction.currency,
            context.localeName,
          )
        : _formatAmount(
            transaction.amount,
            transaction.currency,
            context.localeName,
          );
    final location = transaction.type == 'transfer'
        ? '${_account?.name ?? context.l10n.deletedAccount} → '
              '${_toAccount?.name ?? context.l10n.deletedAccount}'
        : (_account?.name ?? context.l10n.deletedAccount);

    return _ActionCard(
      icon: icon,
      iconColor: color,
      title: context.l10n.transactionName(transaction.name),
      subtitle: '$amountLabel · $location',
      trailing: context.l10n.transactionSaved(
        typeLabel,
        widget.wasUpdated.toString(),
        _formatDate(transaction.date, context.localeName),
      ),
      onEdit: _openEdit,
    );
  }
}

class _TxnEditSheet extends StatefulWidget {
  const _TxnEditSheet({
    required this.repository,
    required this.transaction,
    required this.categories,
    required this.onSaved,
  });

  final TransactionRepository repository;
  final Transaction transaction;
  final List<Category> categories;
  final ValueChanged<Transaction> onSaved;

  @override
  State<_TxnEditSheet> createState() => _TxnEditSheetState();
}

class _TxnEditSheetState extends State<_TxnEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late DateTime _date;
  late String? _categoryId;
  late String _status;
  bool _saving = false;

  Transaction get _transaction => widget.transaction;
  bool get _showAmount =>
      _transaction.type == 'expense' || _transaction.type == 'income';
  bool get _showCategory => _showAmount;
  bool get _showDate => _transaction.type != 'balance_adjustment';
  bool get _showStatus => _transaction.type != 'balance_adjustment';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _transaction.name);
    _amountController = TextEditingController(
      text: _centsToDecimal(_transaction.amount),
    );
    _descriptionController = TextEditingController(
      text: _transaction.description ?? '',
    );
    _date = DateTime.fromMillisecondsSinceEpoch(_transaction.date.toInt());
    _status = _transaction.status;
    _categoryId =
        widget.categories.any(
          (category) => category.id == _transaction.categoryId,
        )
        ? _transaction.categoryId
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.accept,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      final originalDate = DateTime.fromMillisecondsSinceEpoch(
        _transaction.date.toInt(),
      );
      final dateChanged = !_sameCalendarDate(originalDate, _date);
      await widget.repository.update(
        _transaction.id,
        name: Value(_nameController.text.trim()),
        description: Value(description.isEmpty ? null : description),
        date: _showDate && dateChanged
            ? Value(BigInt.from(_date.millisecondsSinceEpoch))
            : const Value.absent(),
        dateConfirmed: _showDate && dateChanged
            ? const Value(true)
            : const Value.absent(),
        timeStatus: _showDate && dateChanged
            ? const Value(TransactionTimeStatus.none)
            : const Value.absent(),
        amount: _showAmount
            ? Value(_decimalToCents(_amountController.text))
            : const Value.absent(),
        categoryId: _showCategory && _categoryId != null
            ? Value(_categoryId!)
            : const Value.absent(),
        status: _showStatus ? Value(_status) : const Value.absent(),
      );
      final updated = await widget.repository.getById(_transaction.id);
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Error updating voice transaction: $error\n$stackTrace');
      if (!mounted) return;
      _showSnack(context, context.l10n.transactionSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheetScaffold(
      formKey: _formKey,
      title: context.l10n.editTransactionType(
        _txnTypeName(_transaction.type, context.l10n),
      ),
      saving: _saving,
      onSave: _submit,
      children: [
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.name,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => _requiredName(context.l10n, value),
        ),
        if (_showAmount) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: '${context.l10n.amount} (${_transaction.currency})',
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) => _positiveAmount(context.l10n, value),
          ),
        ],
        if (_showDate) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.date,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(_formatDateFromDt(_date, context.localeName)),
            ),
          ),
        ],
        if (_showCategory) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: InputDecoration(
              labelText: context.l10n.category,
              border: const OutlineInputBorder(),
            ),
            items: widget.categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _categoryId = value),
            validator: (value) =>
                value == null ? context.l10n.chooseCategory : null,
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionOptional,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        if (_showStatus) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'cleared',
                label: Text(context.l10n.cleared),
              ),
              ButtonSegment(
                value: 'pending',
                label: Text(context.l10n.pending),
              ),
            ],
            selected: {_status},
            onSelectionChanged: (selection) {
              setState(() => _status = selection.single);
            },
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Account preview and editor
// =============================================================================

class _AccountActionWidget extends StatefulWidget {
  const _AccountActionWidget({
    required this.entityId,
    required this.wasUpdated,
  });

  final String entityId;
  final bool wasUpdated;

  @override
  State<_AccountActionWidget> createState() => _AccountActionWidgetState();
}

class _AccountActionWidgetState extends State<_AccountActionWidget> {
  Account? _account;
  bool _loading = true;
  bool _failed = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<AppRepositories>().accounts;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final account = await repository.getById(widget.entityId);
      if (!mounted) return;
      setState(() {
        _account = account;
        _loading = false;
        _failed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Error loading voice account preview: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openEdit() {
    final account = _account;
    if (account == null) return;
    final repository = context.read<AppRepositories>().accounts;
    _showActionEditSheet(
      context,
      _AccountEditSheet(
        repository: repository,
        account: account,
        onSaved: (updated) {
          if (mounted) setState(() => _account = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    if (_failed) return _ActionErrorCard(onRetry: _load);
    final account = _account;
    if (account == null) return const SizedBox.shrink();
    final accent = colorFromHex(account.color, fallback: accountDefaultColor);
    return _ActionCard(
      icon: accountIconFromName(account.icon),
      iconColor: accent,
      title: account.name,
      subtitle: account.currency,
      trailing: widget.wasUpdated
          ? context.l10n.accountUpdated
          : context.l10n.accountCreated,
      onEdit: _openEdit,
    );
  }
}

class _AccountEditSheet extends StatefulWidget {
  const _AccountEditSheet({
    required this.repository,
    required this.account,
    required this.onSaved,
  });

  final AccountRepository repository;
  final Account account;
  final ValueChanged<Account> onSaved;

  @override
  State<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<_AccountEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Color _color;
  late IconData _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _descriptionController = TextEditingController(
      text: widget.account.description ?? '',
    );
    _color = colorFromHex(widget.account.color, fallback: accountDefaultColor);
    _icon = accountIconFromName(widget.account.icon);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showColorPickerDialog(context, selected: _color);
    if (picked != null && mounted) setState(() => _color = picked);
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: accountIconOptions,
      accent: _color,
    );
    if (picked != null && mounted) setState(() => _icon = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      await widget.repository.update(
        widget.account.id,
        name: Value(_nameController.text.trim()),
        description: Value(description.isEmpty ? null : description),
        color: Value(colorToHex(_color)),
        icon: Value(accountIconName(_icon)),
      );
      final updated = await widget.repository.getById(widget.account.id);
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Error updating voice account: $error\n$stackTrace');
      if (mounted) _showSnack(context, context.l10n.accountSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheetScaffold(
      formKey: _formKey,
      title: context.l10n.editAccount,
      saving: _saving,
      onSave: _submit,
      children: [
        TextFormField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.name,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => _requiredName(context.l10n, value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionOptional,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _AppearanceTile(
          label: context.l10n.color,
          leading: CircleAvatar(backgroundColor: _color, radius: 12),
          onTap: _pickColor,
        ),
        _AppearanceTile(
          label: context.l10n.icon,
          leading: Icon(_icon, color: _color),
          onTap: _pickIcon,
        ),
      ],
    );
  }
}

// =============================================================================
// Category preview and editor
// =============================================================================

class _CategoryActionWidget extends StatefulWidget {
  const _CategoryActionWidget({
    required this.entityId,
    required this.wasUpdated,
  });

  final String entityId;
  final bool wasUpdated;

  @override
  State<_CategoryActionWidget> createState() => _CategoryActionWidgetState();
}

class _CategoryActionWidgetState extends State<_CategoryActionWidget> {
  Category? _category;
  bool _loading = true;
  bool _failed = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<AppRepositories>().categories;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final category = await repository.getById(widget.entityId);
      if (!mounted) return;
      setState(() {
        _category = category;
        _loading = false;
        _failed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Error loading voice category preview: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openEdit() {
    final category = _category;
    if (category == null) return;
    final repository = context.read<AppRepositories>().categories;
    _showActionEditSheet(
      context,
      _CategoryEditSheet(
        repository: repository,
        category: category,
        onSaved: (updated) {
          if (mounted) setState(() => _category = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    if (_failed) return _ActionErrorCard(onRetry: _load);
    final category = _category;
    if (category == null) return const SizedBox.shrink();
    final accent = colorFromHex(category.color, fallback: categoryDefaultColor);
    return _ActionCard(
      icon: categoryIconFromName(category.icon),
      iconColor: accent,
      title: category.name,
      subtitle: category.description ?? context.l10n.noDescription,
      trailing: widget.wasUpdated
          ? context.l10n.categoryUpdated
          : context.l10n.categoryCreated,
      onEdit: _openEdit,
    );
  }
}

class _CategoryEditSheet extends StatefulWidget {
  const _CategoryEditSheet({
    required this.repository,
    required this.category,
    required this.onSaved,
  });

  final CategoryRepository repository;
  final Category category;
  final ValueChanged<Category> onSaved;

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Color _color;
  late IconData _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _descriptionController = TextEditingController(
      text: widget.category.description ?? '',
    );
    _color = colorFromHex(
      widget.category.color,
      fallback: categoryDefaultColor,
    );
    _icon = categoryIconFromName(widget.category.icon);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showColorPickerDialog(context, selected: _color);
    if (picked != null && mounted) setState(() => _color = picked);
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPickerDialog(
      context,
      selected: _icon,
      options: categoryIconOptions,
      accent: _color,
    );
    if (picked != null && mounted) setState(() => _icon = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      await widget.repository.update(
        widget.category.id,
        name: Value(_nameController.text.trim()),
        description: Value(description.isEmpty ? null : description),
        color: Value(colorToHex(_color)),
        icon: Value(categoryIconName(_icon)),
      );
      final updated = await widget.repository.getById(widget.category.id);
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Error updating voice category: $error\n$stackTrace');
      if (mounted) _showSnack(context, context.l10n.categorySaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheetScaffold(
      formKey: _formKey,
      title: context.l10n.editCategory,
      saving: _saving,
      onSave: _submit,
      children: [
        TextFormField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.name,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => _requiredName(context.l10n, value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionOptional,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _AppearanceTile(
          label: context.l10n.color,
          leading: CircleAvatar(backgroundColor: _color, radius: 12),
          onTap: _pickColor,
        ),
        _AppearanceTile(
          label: context.l10n.icon,
          leading: Icon(_icon, color: _color),
          onTap: _pickIcon,
        ),
      ],
    );
  }
}

// =============================================================================
// Tag preview and editor
// =============================================================================

class _TagActionWidget extends StatefulWidget {
  const _TagActionWidget({required this.entityId, required this.wasUpdated});

  final String entityId;
  final bool wasUpdated;

  @override
  State<_TagActionWidget> createState() => _TagActionWidgetState();
}

class _TagActionWidgetState extends State<_TagActionWidget> {
  Tag? _tag;
  List<Tag> _tags = const [];
  bool _loading = true;
  bool _failed = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<AppRepositories>().tags;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tag = await repository.getById(widget.entityId);
      final tags = await repository.listActive();
      if (!mounted) return;
      setState(() {
        _tag = tag;
        _tags = tags;
        _loading = false;
        _failed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Error loading voice tag preview: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openEdit() {
    final tag = _tag;
    if (tag == null) return;
    final repository = context.read<AppRepositories>().tags;
    _showActionEditSheet(
      context,
      _TagEditSheet(
        repository: repository,
        tag: tag,
        tags: _tags,
        onSaved: (updated) {
          if (mounted) setState(() => _tag = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    if (_failed) return _ActionErrorCard(onRetry: _load);
    final tag = _tag;
    if (tag == null) return const SizedBox.shrink();
    final accent = colorFromHex(tag.color);
    final parentName = _tags
        .where((candidate) => candidate.id == tag.parentId)
        .map((candidate) => candidate.name)
        .firstOrNull;
    return _ActionCard(
      icon: Icons.label_rounded,
      iconColor: accent,
      title: tag.name,
      subtitle: parentName == null
          ? context.l10n.noParentTag
          : context.l10n.insideTag(parentName),
      trailing: widget.wasUpdated
          ? context.l10n.tagUpdated
          : context.l10n.tagCreated,
      onEdit: _openEdit,
    );
  }
}

class _TagEditSheet extends StatefulWidget {
  const _TagEditSheet({
    required this.repository,
    required this.tag,
    required this.tags,
    required this.onSaved,
  });

  final TagRepository repository;
  final Tag tag;
  final List<Tag> tags;
  final ValueChanged<Tag> onSaved;

  @override
  State<_TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends State<_TagEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Color _color;
  late String? _parentId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tag.name);
    _descriptionController = TextEditingController(
      text: widget.tag.description ?? '',
    );
    _color = colorFromHex(widget.tag.color);
    _parentId = widget.tags.any((tag) => tag.id == widget.tag.parentId)
        ? widget.tag.parentId
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showColorPickerDialog(context, selected: _color);
    if (picked != null && mounted) setState(() => _color = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      await widget.repository.update(
        widget.tag.id,
        name: Value(_nameController.text.trim()),
        description: Value(description.isEmpty ? null : description),
        color: Value(colorToHex(_color)),
        parentId: _parentId == widget.tag.parentId
            ? const Value.absent()
            : Value(_parentId),
      );
      final updated = await widget.repository.getById(widget.tag.id);
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Error updating voice tag: $error\n$stackTrace');
      if (mounted) _showSnack(context, context.l10n.tagSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalidParents = _descendantTagIds(widget.tags, widget.tag.id)
      ..add(widget.tag.id);
    final parentOptions = widget.tags
        .where((tag) => !invalidParents.contains(tag.id))
        .toList();

    return _EditSheetScaffold(
      formKey: _formKey,
      title: context.l10n.editTag,
      saving: _saving,
      onSave: _submit,
      children: [
        TextFormField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.name,
            border: const OutlineInputBorder(),
          ),
          validator: (value) => _requiredName(context.l10n, value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _parentId,
          decoration: InputDecoration(
            labelText: context.l10n.parentTag,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(context.l10n.noParentTag),
            ),
            ...parentOptions.map(
              (tag) => DropdownMenuItem<String?>(
                value: tag.id,
                child: Text(tag.name),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _parentId = value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionOptional,
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _AppearanceTile(
          label: context.l10n.color,
          leading: CircleAvatar(backgroundColor: _color, radius: 12),
          onTap: _pickColor,
        ),
      ],
    );
  }
}

// =============================================================================
// Shared sheet/card UI
// =============================================================================

Future<void> _showActionEditSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => child,
  );
}

class _EditSheetScaffold extends StatelessWidget {
  const _EditSheetScaffold({
    required this.formKey,
    required this.title,
    required this.saving,
    required this.onSave,
    required this.children,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      minimum: const EdgeInsets.only(bottom: 16),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FilledButton(
                    onPressed: saving ? null : onSave,
                    child: saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.l10n.save),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({
    required this.label,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox.square(dimension: 32, child: Center(child: leading)),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onEdit,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      trailing,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onEdit,
                tooltip: context.l10n.edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSkeleton extends StatelessWidget {
  const _ActionSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: MediaQuery.sizeOf(context).width * 0.92,
        height: 72,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            _SkeletonBlock(
              width: 40,
              height: 40,
              radius: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(
                  width: 120,
                  height: 12,
                  radius: 6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
                const SizedBox(height: 6),
                _SkeletonBlock(
                  width: 180,
                  height: 10,
                  radius: 5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ActionErrorCard extends StatelessWidget {
  const _ActionErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ActionCard(
      icon: Icons.error_outline_rounded,
      iconColor: colors.error,
      title: context.l10n.actionLoadFailed,
      subtitle: context.l10n.tapToRetry,
      trailing: '',
      onEdit: onRetry,
    );
  }
}

// =============================================================================
// Pure helpers
// =============================================================================

(IconData, Color, String) _txnTypeConfig(String type, BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return switch (type) {
    'expense' => (
      Icons.arrow_downward_rounded,
      colors.error,
      context.l10n.expense,
    ),
    'income' => (
      Icons.arrow_upward_rounded,
      Colors.green.shade600,
      context.l10n.income,
    ),
    'transfer' => (
      Icons.swap_horiz_rounded,
      colors.primary,
      context.l10n.transfer,
    ),
    _ => (
      Icons.tune_rounded,
      Colors.amber.shade700,
      context.l10n.balanceAdjustment,
    ),
  };
}

String _txnTypeName(String type, AppLocalizations l10n) => switch (type) {
  'expense' => l10n.expense,
  'income' => l10n.income,
  'transfer' => l10n.transfer,
  _ => l10n.balanceAdjustment,
};

String? _requiredName(AppLocalizations l10n, String? value) =>
    value == null || value.trim().isEmpty ? l10n.enterName : null;

String? _positiveAmount(AppLocalizations l10n, String? value) {
  if (value == null || value.trim().isEmpty) return l10n.amountRequired;
  final cents = _tryDecimalToCents(value);
  if (cents == null || cents <= BigInt.zero) {
    return l10n.amountGreaterThanZero;
  }
  return null;
}

BigInt _decimalToCents(String value) => _tryDecimalToCents(value)!;

BigInt? _tryDecimalToCents(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{0,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = BigInt.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  return whole * BigInt.from(100) + BigInt.parse(fraction.padRight(2, '0'));
}

String _centsToDecimal(BigInt cents) {
  final negative = cents.isNegative;
  final absolute = cents.abs();
  final sign = negative ? '-' : '';
  return '$sign${absolute ~/ BigInt.from(100)}.'
      '${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String _formatAmount(BigInt cents, String currency, String locale) =>
    formatMoney(cents.toInt(), currency, locale: locale);

String _formatDate(BigInt epochMs, String locale) => _formatDateFromDt(
  DateTime.fromMillisecondsSinceEpoch(epochMs.toInt()),
  locale,
);

String _formatDateFromDt(DateTime date, String locale) =>
    formatNumericDate(date, locale);

bool _sameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

Set<String> _descendantTagIds(List<Tag> tags, String rootId) {
  final descendants = <String>{};
  final queue = <String>[rootId];
  while (queue.isNotEmpty) {
    final parentId = queue.removeAt(0);
    for (final tag in tags) {
      if (tag.parentId == parentId && descendants.add(tag.id)) {
        queue.add(tag.id);
      }
    }
  }
  return descendants;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
