import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/screens/create_account.dart';
import 'package:app/screens/edit_account.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _isManagementMode = false;
  final Set<String> _selectedIds = {};

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
      await context.read<AppRepositories>().accounts.archive(id);
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
      final repos = context.read<AppRepositories>();
      await Future.wait(ids.map(repos.accounts.archive));
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
    final repos = context.read<AppRepositories>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const CreateAccountScreen(),
        ),
      ),
    );
  }

  void _navigateToEditAccount(Account account) {
    final db = context.read<AppDatabase>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Provider<AppDatabase>.value(
          value: db,
          child: EditAccountScreen(account: account),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    final selCount = _selectedIds.length;

    return Scaffold(
      appBar: AppBar(
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
      body: Column(
        children: [
          Expanded(
            child: _AccountsList(
              repos: repos,
              isManagementMode: _isManagementMode,
              selectedIds: _selectedIds,
              onEdit: _navigateToEditAccount,
              onDelete: _requestDelete,
              onLongPress: _enterManagementMode,
              onToggleSelect: _toggleSelection,
              onCreateTap: _navigateToCreateAccount,
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
  }
}

// ── Accounts list ─────────────────────────────────────────────────────────────

// Stateful so the stream is created once in initState and reused across
// parent rebuilds (e.g. selection toggles). Passing a new stream object to
// StreamBuilder on each build causes it to briefly reset to waiting state,
// which flashes the loading indicator.
class _AccountsList extends StatefulWidget {
  const _AccountsList({
    required this.repos,
    required this.isManagementMode,
    required this.selectedIds,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onCreateTap,
  });

  final AppRepositories repos;
  final bool isManagementMode;
  final Set<String> selectedIds;
  final void Function(Account) onEdit;
  final void Function(String, String) onDelete;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;
  final VoidCallback onCreateTap;

  @override
  State<_AccountsList> createState() => _AccountsListState();
}

class _AccountsListState extends State<_AccountsList> {
  late final Stream<List<Account>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repos.accounts.watchActive();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Account>>(
      stream: _stream,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final list = snapshot.data ?? [];

        if (loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return _EmptyBody(onCreateTap: widget.onCreateTap);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final account = list[i];
            return _AccountCard(
              account: account,
              isManagementMode: widget.isManagementMode,
              isSelected: widget.selectedIds.contains(account.id),
              onEdit: () => widget.onEdit(account),
              onDelete: () => widget.onDelete(account.id, account.name),
              onLongPress: () => widget.onLongPress(account.id),
              onToggleSelect: () => widget.onToggleSelect(account.id),
            );
          },
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
    required this.isManagementMode,
    required this.isSelected,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  final Account account;
  final bool isManagementMode;
  final bool isSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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

    final Widget trailing = isManagementMode
        ? Chip(label: Text(account.currency))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(label: Text(account.currency)),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                iconSize: 20,
                style: compactIcon(),
                onPressed: onEdit,
                tooltip: 'Editar',
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: leading,
        title: Text(account.name),
        trailing: trailing,
        onTap: isManagementMode ? onToggleSelect : null,
        onLongPress: isManagementMode ? null : onLongPress,
      ),
    );
  }
}
