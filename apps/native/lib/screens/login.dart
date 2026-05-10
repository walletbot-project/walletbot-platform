import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final accounts = auth.accounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (accounts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Continue as',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final account in accounts)
              Card(
                child: ListTile(
                  leading: Icon(
                    account.type == AccountType.local
                        ? Icons.person_outline
                        : Icons.cloud_outlined,
                  ),
                  title: Text(account.name ?? account.email ?? 'Local account'),
                  subtitle: Text(
                    account.type == AccountType.local ? 'Local' : 'Online',
                  ),
                  onTap: () => context.read<AuthController>().switchTo(
                    account.id,
                  ),
                ),
              ),
            const Divider(height: 32),
          ],
          FilledButton.icon(
            onPressed: () => context.read<AuthController>().addLocal(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Continue without account'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Google sign-in not implemented yet'),
                ),
              );
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }
}
