import 'package:app/database.dart';
import 'package:app/screens/create_account.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<Account>>(
      stream: db.watchAccounts(),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final list = snapshot.data ?? [];

        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: CustomScrollView(
            slivers: [
              const SliverAppBar.large(title: Text('Cuentas')),
              if (loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                const SliverFillRemaining(child: _EmptyBody())
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => _AccountCard(account: list[i]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverToBoxAdapter(
                    child: FilledButton.icon(
                      onPressed: () {
                        final db = context.read<AppDatabase>();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Provider<AppDatabase>.value(
                              value: db,
                              child: const CreateAccountScreen(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Crear cuenta'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

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
            onPressed: () {
              final db = context.read<AppDatabase>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Provider<AppDatabase>.value(
                    value: db,
                    child: const CreateAccountScreen(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Crear cuenta'),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.account_balance_wallet_rounded,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(account.name),
        trailing: Chip(label: Text(account.currency)),
      ),
    );
  }
}
