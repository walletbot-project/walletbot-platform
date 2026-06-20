import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/data/data.dart';
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
  void showUserMenu() {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) {
        final auth = context.watch<AuthController>();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Accounts'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: ListView(
              children: [
                for (final account in auth.accounts)
                  ListTile(
                    leading: Icon(
                      account.type == AccountType.local
                          ? Icons.person_outline
                          : Icons.cloud_outlined,
                    ),
                    title: Text(
                      account.name ?? account.email ?? 'Local account',
                    ),
                    subtitle: Text(
                      account.type == AccountType.local ? 'Local' : 'Online',
                    ),
                    trailing: account.id == auth.activeId
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () async {
                      if (account.id != auth.activeId) {
                        await auth.switchTo(account.id);
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () async {
                    Navigator.pop(context);
                    await auth.signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManualAdd() async {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const TransactionFormScreen(),
        ),
      ),
    );
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
            onPressed: showUserMenu,
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
