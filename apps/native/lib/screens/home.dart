import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart';
import 'package:app/screens/setup-accounts.dart';
import 'package:app/sync/sync_status_pill.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _testResult;
  bool _testing = false;

  Future<void> _runTestQuery() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final result = await ConvexClient.instance.query('test:hello', {});
      if (!mounted) return;
      setState(() => _testResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _navigateToSetupAccounts() {
    final db = context.read<AppDatabase>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Provider<AppDatabase>.value(
          value: db,
          child: const SetupAccountsScreen(),
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

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
      body: StreamBuilder<List<Account>>(
        stream: db.watchAccounts(),
        builder: (context, snapshot) {
          final hasNoAccounts =
              snapshot.connectionState != ConnectionState.waiting &&
              (snapshot.data?.isEmpty ?? true);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasNoAccounts) ...[
                  _NoAccountsBanner(onSetup: _navigateToSetupAccounts),
                  const SizedBox(height: 16),
                ],
                const Text('Home Screen'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _testing ? null : _runTestQuery,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_rounded),
                  label: const Text('Test Convex query (test:hello)'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _testResult!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── No-accounts banner ────────────────────────────────────────────────────────

class _NoAccountsBanner extends StatelessWidget {
  const _NoAccountsBanner({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.secondary,
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: colorScheme.onSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configurá tus cuentas',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        'Registrá tus cuentas y balances iniciales para empezar.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSetup,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Empezar'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondary,
                foregroundColor: colorScheme.onSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

