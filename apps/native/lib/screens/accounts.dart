import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/screens/create_account.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  void _openCreate(BuildContext context) {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
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

  @override
  Widget build(BuildContext context) {
    final repos = context.read<AppRepositories>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas'),
        actions: [
          IconButton(
            tooltip: 'Nueva cuenta',
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Account>>(
        stream: repos.accounts.watchActive(),
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final list = snapshot.data ?? [];

          if (loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return _EmptyBody(onCreateTap: () => _openCreate(context));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: list.length,
            itemBuilder: (context, i) => _AccountCard(account: list[i]),
          );
        },
      ),
    );
  }
}

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
