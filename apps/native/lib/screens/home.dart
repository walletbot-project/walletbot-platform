import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
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
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('Add account'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: showUserMenu,
            icon: const Icon(Icons.person_rounded),
          ),
        ],
      ),
      body: const Center(child: Text('Home Screen')),
    );
  }
}
