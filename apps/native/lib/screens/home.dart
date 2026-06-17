import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/pop_on_account_switch.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/sync/sync_status_pill.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _showAccountSwitcher() {
    showDialog<void>(
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TransactionFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: SyncStatusPill()),
          ),
          IconButton(
            onPressed: _showAccountSwitcher,
            icon: const Icon(Icons.person_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
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
