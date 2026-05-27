import 'package:app/components/currency-picker.dart';
import 'package:app/database.dart';
import 'package:app/screens/create_account.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  // Null means no account is being edited.
  String? _editingAccountId;
  final _editController = TextEditingController();
  // Pending currency while an edit is in progress.
  String _editCurrency = '';

  bool _isManagementMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  // ── Edit ────────────────────────────────────────────────────────────────────

  void _startEdit(String id, String currentName, String currentCurrency) {
    _editController.text = currentName;
    _editController.selection =
        TextSelection.fromPosition(TextPosition(offset: currentName.length));
    setState(() {
      _editingAccountId = id;
      _editCurrency = currentCurrency;
    });
  }

  Future<void> _pickEditCurrency() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CurrencyPickerSheet(selected: _editCurrency),
    );
    if (picked != null && mounted) {
      setState(() => _editCurrency = picked);
    }
  }

  Future<void> _confirmEdit() async {
    final id = _editingAccountId;
    if (id == null) return;

    final newName = _editController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío')),
      );
      return;
    }

    // Snapshot before clearing state so the async call has the right values.
    final currency = _editCurrency;

    // Close edit mode before the async call so the UI is never stuck.
    setState(() => _editingAccountId = null);

    try {
      await context.read<AppDatabase>().updateAccount(id, newName, currency);
    } catch (e, st) {
      debugPrint('Error updating account: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar los cambios')),
        );
      }
    }
  }

  void _cancelEdit() => setState(() => _editingAccountId = null);

  // ── Delete (single) ─────────────────────────────────────────────────────────

  Future<void> _requestDelete(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cuenta?'),
        content: Text('Se eliminará "$name" de forma permanente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AppDatabase>().archiveAccount(id);
    } catch (e, st) {
      debugPrint('Error archiving account: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al eliminar la cuenta')),
        );
      }
    }
  }

  // ── Management mode (multi-select) ──────────────────────────────────────────

  void _enterManagementMode(String id) {
    setState(() {
      _isManagementMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitManagementMode() {
    setState(() {
      _isManagementMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          count == 1 ? '¿Eliminar 1 cuenta?' : '¿Eliminar $count cuentas?',
        ),
        content: Text(
          count == 1
              ? 'Se eliminará 1 cuenta de forma permanente.'
              : 'Se eliminarán $count cuentas de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(count == 1 ? 'Eliminar' : 'Eliminar $count'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Snapshot IDs and exit management mode before async work so the UI
    // updates immediately and the user can keep interacting.
    final ids = Set<String>.from(_selectedIds);
    _exitManagementMode();

    try {
      final db = context.read<AppDatabase>();
      await Future.wait(ids.map(db.archiveAccount));
    } catch (e, st) {
      debugPrint('Error archiving accounts: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al eliminar las cuentas')),
        );
      }
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _navigateToCreateAccount() {
    final db = context.read<AppDatabase>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Provider<AppDatabase>.value(
          value: db,
          child: const CreateAccountScreen(),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final selCount = _selectedIds.length;

    return StreamBuilder<List<Account>>(
      stream: db.watchAccounts(),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final list = snapshot.data ?? [];

        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      title: _isManagementMode
                          ? Text(
                              selCount == 0
                                  ? 'Seleccionando'
                                  : selCount == 1
                                      ? '1 cuenta'
                                      : '$selCount cuentas',
                            )
                          : const Text('Cuentas'),
                      actions: [
                        if (!_isManagementMode)
                          IconButton(
                            tooltip: 'Nueva cuenta',
                            onPressed: _navigateToCreateAccount,
                            icon: const Icon(Icons.add),
                          ),
                      ],
                    ),
                    if (loading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (list.isEmpty)
                      SliverFillRemaining(
                        child: _EmptyBody(
                          onCreateTap: _navigateToCreateAccount,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        sliver: SliverList.builder(
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final account = list[i];
                            final isEditing =
                                _editingAccountId == account.id;
                            return _AccountCard(
                              account: account,
                              isEditing: isEditing,
                              editController: _editController,
                              editCurrency: isEditing
                                  ? _editCurrency
                                  : account.currency,
                              isManagementMode: _isManagementMode,
                              isSelected: _selectedIds.contains(account.id),
                              onStartEdit: () => _startEdit(
                                account.id,
                                account.name,
                                account.currency,
                              ),
                              onConfirmEdit: _confirmEdit,
                              onCancelEdit: _cancelEdit,
                              onTapCurrency: _pickEditCurrency,
                              onDelete: () =>
                                  _requestDelete(account.id, account.name),
                              onLongPress: () =>
                                  _enterManagementMode(account.id),
                              onToggleSelect: () =>
                                  _toggleSelection(account.id),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              // Management mode action bar — rendered outside the scroll view
              // so it always sits above the NavigationBar and the Android system
              // navigation area regardless of scroll position.
              if (_isManagementMode)
                _ManagementBar(
                  selectedCount: selCount,
                  onCancel: _exitManagementMode,
                  onDelete: selCount > 0 ? _deleteSelected : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No tenés cuentas aún',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Creá tu primera cuenta para empezar a registrar tus gastos.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: const Text('Crear cuenta'),
          ),
        ],
      ),
    );
  }
}

// ── Management mode bottom bar ───────────────────────────────────────────────

class _ManagementBar extends StatelessWidget {
  const _ManagementBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onCancel;
  // Null when nothing is selected — disables the delete button.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = selectedCount == 0
        ? 'Eliminar'
        : selectedCount == 1
            ? 'Eliminar 1'
            : 'Eliminar $selectedCount';

    // SafeArea(top: false) ensures the bar clears the Android system
    // navigation bar (gesture strip or 3-button bar) without adding
    // redundant top padding.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onDelete,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account tile ─────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.isEditing,
    required this.editController,
    required this.editCurrency,
    required this.isManagementMode,
    required this.isSelected,
    required this.onStartEdit,
    required this.onConfirmEdit,
    required this.onCancelEdit,
    required this.onTapCurrency,
    required this.onDelete,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  final Account account;
  final bool isEditing;
  final TextEditingController editController;
  // Current pending currency while editing; equals account.currency otherwise.
  final String editCurrency;
  final bool isManagementMode;
  final bool isSelected;
  final VoidCallback onStartEdit;
  final VoidCallback onConfirmEdit;
  final VoidCallback onCancelEdit;
  // Opens the currency picker when in edit mode.
  final VoidCallback onTapCurrency;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Compact icon buttons to fit alongside the currency chip.
    ButtonStyle compactIcon() => IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );

    final Widget leading = isManagementMode
        ? Checkbox(
            value: isSelected,
            onChanged: (_) => onToggleSelect(),
          )
        : CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
          );

    final Widget title = isEditing
        ? TextField(
            controller: editController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
            ),
            onSubmitted: (_) => onConfirmEdit(),
          )
        : Text(account.name);

    final Widget trailing;
    if (isEditing) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionChip(
            label: Text(editCurrency),
            avatar: const Icon(Icons.arrow_drop_down, size: 18),
            onPressed: onTapCurrency,
            tooltip: 'Cambiar moneda',
          ),
          IconButton(
            icon: Icon(Icons.check_rounded, color: Colors.green.shade700),
            iconSize: 20,
            style: compactIcon(),
            onPressed: onConfirmEdit,
            tooltip: 'Confirmar',
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: colorScheme.error),
            iconSize: 20,
            style: compactIcon(),
            onPressed: onCancelEdit,
            tooltip: 'Cancelar',
          ),
        ],
      );
    } else if (isManagementMode) {
      trailing = Chip(label: Text(account.currency));
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(label: Text(account.currency)),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            iconSize: 20,
            style: compactIcon(),
            onPressed: onStartEdit,
            tooltip: 'Editar nombre',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            iconSize: 20,
            style: compactIcon(),
            onPressed: onDelete,
            tooltip: 'Eliminar',
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: leading,
        title: title,
        trailing: trailing,
        // In management mode the whole tile toggles selection; in normal mode
        // a long-press enters management mode.
        onTap: isManagementMode ? onToggleSelect : null,
        onLongPress: isManagementMode ? null : onLongPress,
      ),
    );
  }
}
