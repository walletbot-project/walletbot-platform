import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
// ignore: implementation_imports
import 'package:convex_dart/src/convex_dart_for_generated_code.dart'
    show InternalConvexClient, encodeMap;
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
      final result = await InternalConvexClient.instance.query(
        name: 'test:hello',
        args: encodeMap({}),
      );
      setState(() => _testResult = result.toString());
    } catch (e) {
      setState(() => _testResult = 'ERROR: $e');
    } finally {
      setState(() => _testing = false);
    }
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
      ),
    );
  }
}
