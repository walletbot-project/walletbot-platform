import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database.dart';

const kEditableToolNames = <String>{
  'addExpense',
  'addIncome',
  'addTransfer',
  'addBalanceAdjustment',
  'createAccount',
  'createCategory',
};

bool isEditableTool(String name) => kEditableToolNames.contains(name);

// =============================================================================
// Main dispatcher
// =============================================================================

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
      'createAccount' => _AccountActionWidget(entityId: entityId),
      'createCategory' => _CategoryActionWidget(entityId: entityId),
      _ => _TxnActionWidget(toolName: toolName, entityId: entityId),
    };
  }
}

// =============================================================================
// Transaction action widget
// =============================================================================

class _TxnActionWidget extends StatefulWidget {
  const _TxnActionWidget({required this.toolName, required this.entityId});

  final String toolName;
  final String entityId;

  @override
  State<_TxnActionWidget> createState() => _TxnActionWidgetState();
}

class _TxnActionWidgetState extends State<_TxnActionWidget> {
  Transaction? _txn;
  Account? _account;
  List<Category> _categories = [];
  bool _loading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    try {
      final txn = await (db.select(db.transactions)
            ..where((t) => t.id.equals(widget.entityId)))
          .getSingleOrNull();
      if (!mounted) return;
      if (txn == null) {
        setState(() => _loading = false);
        return;
      }
      final account = await (db.select(db.accounts)
            ..where((a) => a.id.equals(txn.accountId)))
          .getSingleOrNull();
      if (!mounted) return;
      final cats = await (db.select(db.categories)
            ..where((c) => c.archived.equals(false)))
          .get();
      if (!mounted) return;
      setState(() {
        _txn = txn;
        _account = account;
        _categories = cats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openEdit() {
    final txn = _txn;
    if (txn == null) return;
    final db = context.read<AppDatabase>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TxnEditSheet(
        db: db,
        transaction: txn,
        categories: _categories,
        onSaved: (updated) {
          if (mounted) setState(() => _txn = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    final txn = _txn;
    if (txn == null) return const SizedBox.shrink();

    final (icon, color, typeLabel) = _txnTypeConfig(txn.type, context);

    return _ActionCard(
      icon: icon,
      iconColor: color,
      title: txn.name,
      subtitle: _formatAmount(txn.amount, txn.currency) +
          (_account != null ? ' · ${_account!.name}' : ''),
      trailing: '$typeLabel · ${_formatDate(txn.date)}',
      onEdit: _openEdit,
    );
  }
}

(IconData, Color, String) _txnTypeConfig(String type, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return switch (type) {
    'expense' => (Icons.arrow_downward_rounded, cs.error, 'Gasto'),
    'income' => (Icons.arrow_upward_rounded, Colors.green.shade600, 'Ingreso'),
    'transfer' => (Icons.swap_horiz_rounded, cs.primary, 'Transferencia'),
    _ => (Icons.tune_rounded, cs.onSurfaceVariant, 'Ajuste'),
  };
}

// =============================================================================
// Transaction edit sheet
// =============================================================================

class _TxnEditSheet extends StatefulWidget {
  const _TxnEditSheet({
    required this.db,
    required this.transaction,
    required this.categories,
    required this.onSaved,
  });

  final AppDatabase db;
  final Transaction transaction;
  final List<Category> categories;
  final void Function(Transaction updated) onSaved;

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

  @override
  void initState() {
    super.initState();
    final txn = widget.transaction;
    _nameController = TextEditingController(text: txn.name);
    _amountController = TextEditingController(text: _centsToDecimal(txn.amount));
    _descriptionController = TextEditingController(text: txn.description ?? '');
    _date = DateTime.fromMillisecondsSinceEpoch(txn.date.toInt());
    _status = txn.status;
    final rawCatId = txn.categoryId.isEmpty ? null : txn.categoryId;
    _categoryId =
        widget.categories.any((c) => c.id == rawCatId) ? rawCatId : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _centsToDecimal(BigInt cents) =>
      (cents.toDouble() / 100).toStringAsFixed(2);

  BigInt _decimalToCents(String s) {
    final val = double.parse(s.trim().replaceAll(',', '.'));
    return BigInt.from((val * 100).round());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final txn = widget.transaction;
      final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
      final dateMs = BigInt.from(_date.millisecondsSinceEpoch);
      final desc = _descriptionController.text.trim();

      final isBalanceAdj = txn.type == 'balance_adjustment';
      final companion = isBalanceAdj
          ? TransactionsCompanion(
              name: Value(_nameController.text.trim()),
              description: Value(desc.isEmpty ? null : desc),
              date: Value(dateMs),
              updatedAt: Value(now),
              dirty: const Value(true),
            )
          : TransactionsCompanion(
              name: Value(_nameController.text.trim()),
              description: Value(desc.isEmpty ? null : desc),
              date: Value(dateMs),
              amount: Value(_decimalToCents(_amountController.text)),
              categoryId: _categoryId != null
                  ? Value(_categoryId!)
                  : const Value.absent(),
              status: Value(_status),
              updatedAt: Value(now),
              dirty: const Value(true),
            );

      await (widget.db.update(widget.db.transactions)
            ..where((t) => t.id.equals(txn.id)))
          .write(companion);
      if (!mounted) return;
      final updated = await (widget.db.select(widget.db.transactions)
            ..where((t) => t.id.equals(txn.id)))
          .getSingleOrNull();
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txn = widget.transaction;
    final isBalanceAdj = txn.type == 'balance_adjustment';
    final showCategory = txn.type == 'expense' || txn.type == 'income';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar ${_txnTypeName(txn.type)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            if (!isBalanceAdj) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Monto (${txn.currency})',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá el monto';
                  if (double.tryParse(v.trim().replaceAll(',', '.')) == null) {
                    return 'Monto inválido';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_formatDateFromDt(_date)),
              ),
            ),
            if (showCategory && widget.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                items: widget.categories
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            if (!isBalanceAdj) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Estado:', style: theme.textTheme.bodyMedium),
                  ChoiceChip(
                    label: const Text('Liquidado'),
                    selected: _status == 'cleared',
                    onSelected: (_) => setState(() => _status = 'cleared'),
                  ),
                  ChoiceChip(
                    label: const Text('Pendiente'),
                    selected: _status == 'pending',
                    onSelected: (_) => setState(() => _status = 'pending'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

String _txnTypeName(String type) => switch (type) {
      'expense' => 'gasto',
      'income' => 'ingreso',
      'transfer' => 'transferencia',
      _ => 'ajuste',
    };

// =============================================================================
// Account action widget
// =============================================================================

class _AccountActionWidget extends StatefulWidget {
  const _AccountActionWidget({required this.entityId});

  final String entityId;

  @override
  State<_AccountActionWidget> createState() => _AccountActionWidgetState();
}

class _AccountActionWidgetState extends State<_AccountActionWidget> {
  Account? _account;
  bool _loading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    try {
      final acc = await (db.select(db.accounts)
            ..where((a) => a.id.equals(widget.entityId)))
          .getSingleOrNull();
      if (!mounted) return;
      setState(() {
        _account = acc;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openEdit() {
    final acc = _account;
    if (acc == null) return;
    final db = context.read<AppDatabase>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountEditSheet(
        db: db,
        account: acc,
        onSaved: (updated) {
          if (mounted) setState(() => _account = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    final acc = _account;
    if (acc == null) return const SizedBox.shrink();

    return _ActionCard(
      icon: Icons.account_balance_wallet_rounded,
      iconColor: Theme.of(context).colorScheme.primary,
      title: acc.name,
      subtitle: acc.currency,
      trailing: 'Nueva cuenta',
      onEdit: _openEdit,
    );
  }
}

class _AccountEditSheet extends StatefulWidget {
  const _AccountEditSheet({
    required this.db,
    required this.account,
    required this.onSaved,
  });

  final AppDatabase db;
  final Account account;
  final void Function(Account updated) onSaved;

  @override
  State<_AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<_AccountEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
      await (widget.db.update(widget.db.accounts)
            ..where((a) => a.id.equals(widget.account.id)))
          .write(
        AccountsCompanion(
          name: Value(_nameController.text.trim()),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      if (!mounted) return;
      final updated = await (widget.db.select(widget.db.accounts)
            ..where((a) => a.id.equals(widget.account.id)))
          .getSingleOrNull();
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar cuenta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Category action widget
// =============================================================================

class _CategoryActionWidget extends StatefulWidget {
  const _CategoryActionWidget({required this.entityId});

  final String entityId;

  @override
  State<_CategoryActionWidget> createState() => _CategoryActionWidgetState();
}

class _CategoryActionWidgetState extends State<_CategoryActionWidget> {
  Category? _category;
  bool _loading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    try {
      final cat = await (db.select(db.categories)
            ..where((c) => c.id.equals(widget.entityId)))
          .getSingleOrNull();
      if (!mounted) return;
      setState(() {
        _category = cat;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openEdit() {
    final cat = _category;
    if (cat == null) return;
    final db = context.read<AppDatabase>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditSheet(
        db: db,
        category: cat,
        onSaved: (updated) {
          if (mounted) setState(() => _category = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActionSkeleton();
    final cat = _category;
    if (cat == null) return const SizedBox.shrink();

    return _ActionCard(
      icon: Icons.label_rounded,
      iconColor: Theme.of(context).colorScheme.secondary,
      title: cat.name,
      subtitle: cat.description ?? 'Sin descripción',
      trailing: 'Nueva categoría',
      onEdit: _openEdit,
    );
  }
}

class _CategoryEditSheet extends StatefulWidget {
  const _CategoryEditSheet({
    required this.db,
    required this.category,
    required this.onSaved,
  });

  final AppDatabase db;
  final Category category;
  final void Function(Category updated) onSaved;

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _descriptionController = TextEditingController(
      text: widget.category.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
      final desc = _descriptionController.text.trim();
      await (widget.db.update(widget.db.categories)
            ..where((c) => c.id.equals(widget.category.id)))
          .write(
        CategoriesCompanion(
          name: Value(_nameController.text.trim()),
          description: Value(desc.isEmpty ? null : desc),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      if (!mounted) return;
      final updated = await (widget.db.select(widget.db.categories)
            ..where((c) => c.id.equals(widget.category.id)))
          .getSingleOrNull();
      if (!mounted) return;
      if (updated != null) widget.onSaved(updated);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar categoría',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================

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
          maxWidth: MediaQuery.of(context).size.width * 0.92,
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
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Container(
          height: 64,
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

String _formatDate(BigInt epochMs) =>
    _formatDateFromDt(DateTime.fromMillisecondsSinceEpoch(epochMs.toInt()));

String _formatDateFromDt(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return '$dd/$mm/${dt.year}';
}

String _formatAmount(BigInt cents, String currency) =>
    '$currency ${(cents.toDouble() / 100).toStringAsFixed(2)}';
