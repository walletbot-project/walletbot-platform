import 'dart:async';

import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/home.dart';
import 'package:app/screens/insights.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/gemini_voice_expense_command.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadAppConfig();

  await ConvexClient.initialize(
    ConvexConfig(
      deploymentUrl: AppConfig.convexUrl,
      clientId: 'wallet-bot-flutter-1.0',
    ),
  );

  await GoogleSignIn.instance.initialize(
    serverClientId: AppConfig.googleServerClientId,
  );

  final auth = AuthController();
  await auth.load();
  runApp(MyApp(auth: auth));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: MaterialApp(
        title: 'Wallet Bot',
        theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.greenAccent)),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final active = context.watch<AuthController>().activeAccount;
    if (active == null) return const LoginScreen();
    return Provider<AppDatabase>(
      key: ValueKey(active.id),
      create: (_) => AppDatabase.forUser(active.id),
      dispose: (_, db) => db.close(),
      child: const AppMain(),
    );
  }
}

class AppMain extends StatefulWidget {
  const AppMain({super.key});

  @override
  State<AppMain> createState() => _AppMainState();
}

class _AppMainState extends State<AppMain> {
  @override
  void initState() {
    super.initState();
  }

  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final needsReauth = context.select<AuthController, bool>(
      (a) => a.activeAccount?.requiresReauth ?? false,
    );
    return Scaffold(
      body: Column(
        children: [
          if (needsReauth) const _ReauthBanner(),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                HomeScreen(),
                ActivityScreen(),
                Placeholder(),
                InsightsScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final database = context.read<AppDatabase>();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VoiceScreen(
                commandFactory: GeminiVoiceExpenseCommandFactory(
                  database: database,
                  convexSiteUrl: AppConfig.convexSiteUrl,
                ),
              ),
            ),
          );
        },
        tooltip: 'Voice commands',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(
            icon: Icon(Icons.list_rounded),
            label: "Activity",
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_rounded),
            label: "Cuentas",
          ),
          NavigationDestination(
            icon: Icon(Icons.stacked_line_chart_rounded),
            label: "Insights",
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class _ReauthBanner extends StatelessWidget {
  const _ReauthBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sync paused — sign in again to reconnect',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await context.read<AuthController>().signInWithGoogle();
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Reconnect failed: $e')),
                    );
                  }
                },
                child: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
