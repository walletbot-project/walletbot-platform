import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/pop_on_account_switch.dart';
import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_section.dart';
import 'package:app/components/dashboard/default_dashboard.dart';
import 'package:app/data/data.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/sync/sync_status_pill.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenActivity});

  final ValueChanged<TransactionFilter> onOpenActivity;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _maybeSeedDashboard();
  }

  /// Seeds the default dashboard once per device (the repository enforces the
  /// empty-table + one-time guard). Fire-and-forget: the dashboard stream
  /// updates reactively once the rows land.
  void _maybeSeedDashboard() {
    final repos = context.read<AppRepositories>();
    repos.dashboard
        .seedDefaultIfEmpty(() => writeDefaultDashboardSeed(repos))
        .catchError((Object e, StackTrace st) {
          debugPrint('home: default dashboard seed failed: $e');
        });
  }

  void showUserMenu() {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        final auth = dialogContext.watch<AuthController>();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Tus cuentas'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            body: ListView(
              children: [
                for (final account in auth.accounts)
                  ListTile(
                    leading: _AccountAvatar(account: account),
                    title: Text(account.name ?? account.email ?? 'Sin nombre'),
                    subtitle: Text(
                      account.type == AccountType.local
                          ? 'Sin cuenta'
                          : account.email ?? 'Con cuenta',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (account.id == auth.activeId)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check_circle),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: 'Quitar cuenta',
                          onPressed: () =>
                              _confirmRemoveAccount(dialogContext, account),
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (account.id != auth.activeId) {
                        await auth.switchTo(account.id);
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Agregar cuenta'),
                  onTap: () {
                    final previousId = auth.activeId;
                    Navigator.pop(dialogContext);
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PopOnAccountSwitch(
                          accountId: previousId,
                          child: const LoginScreen(canDismiss: true),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRemoveAccount(
    BuildContext dialogContext,
    UserAccount account,
  ) async {
    final auth = dialogContext.read<AuthController>();
    final label = account.name ?? account.email ?? 'esta cuenta';
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Quitar cuenta'),
        content: Text(
          'Se eliminarán los datos de "$label" de este dispositivo. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final wasActive = account.id == auth.activeId;
    try {
      if (account.type == AccountType.local) {
        await auth.deleteLocal(account.id);
      } else {
        await auth.signOutRemote(account.id);
      }
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('No se pudo quitar la cuenta: $e')),
        );
      }
      return;
    }

    // Removing the active account drops us back to the login screen; close the
    // switcher so it is not left floating above it.
    if (wasActive && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }

  Future<void> _openManualAdd() async {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const TransactionFormScreen(),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    context.read<AppNavigation>().index = AppNavigation.activityTab;
  }

  bool _editing = false;

  Future<void> _openAddWidget() async {
    final repos = context.read<AppRepositories>();
    await showAddWidgetSheet(context, repos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: _editing
            ? [
                IconButton(
                  tooltip: 'Agregar widget',
                  onPressed: _openAddWidget,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: 'Listo',
                  onPressed: () => setState(() => _editing = false),
                  icon: const Icon(Icons.check_rounded),
                ),
              ]
            : [
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Center(child: SyncStatusPill()),
                ),
                IconButton(
                  tooltip: 'Editar tablero',
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: showUserMenu,
                  icon: const Icon(Icons.person_rounded),
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DashboardSection(
            editing: _editing,
            onStartEditing: () => setState(() => _editing = true),
            onOpenFilter: widget.onOpenActivity,
          ),
          const SizedBox(height: 24),
          Text('Acciones', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _HomeActionCard(
              label: 'Agregar a mano',
              icon: Icons.add_rounded,
              onTap: _openManualAdd,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 112,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD3CCD8), width: 1.4),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF21C4B6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1,
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

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final UserAccount account;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLocal = account.type == AccountType.local;
    final picture = account.picture;

    return CircleAvatar(
      radius: 20,
      backgroundColor: isLocal
          ? colors.secondaryContainer
          : colors.tertiaryContainer,
      foregroundColor: isLocal
          ? colors.onSecondaryContainer
          : colors.onTertiaryContainer,
      backgroundImage: picture == null ? null : NetworkImage(picture),
      child: picture == null
          ? Icon(isLocal ? Icons.person_outline : Icons.cloud_outlined)
          : null,
    );
  }
}
