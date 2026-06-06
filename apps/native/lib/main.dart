import 'dart:async';

import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
import 'package:app/screens/accounts.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/home.dart';
import 'package:app/screens/insights.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/voice.dart';
import 'package:app/sync/sync_engine.dart';
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
    return MultiProvider(
      key: ValueKey(active.id),
      providers: [
        Provider<AppDatabase>(
          create: (_) => AppDatabase.forUser(active.id),
          dispose: (_, db) => db.close(),
        ),
        // SyncEngine only attaches for remote accounts. For local accounts
        // we still create one (so `Provider.of<SyncEngine>` is non-null
        // throughout the tree) but never call `.start()`, keeping it inert.
        ChangeNotifierProvider<SyncEngine>(
          create: (ctx) => SyncEngine(
            db: ctx.read<AppDatabase>(),
            client: ConvexClient.instance,
          ),
        ),
      ],
      child: const _SyncStarter(child: AppMain()),
    );
  }
}

/// Kicks the sync engine on first build, once both the database and the
/// `AuthController` agree that we have a remote account attached.
class _SyncStarter extends StatefulWidget {
  const _SyncStarter({required this.child});
  final Widget child;

  @override
  State<_SyncStarter> createState() => _SyncStarterState();
}

class _SyncStarterState extends State<_SyncStarter> {
  bool _kicked = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final active = auth.activeAccount;
    if (!_kicked && active != null && active.sessionToken != null) {
      _kicked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(context.read<SyncEngine>().start());
      });
    }
    return widget.child;
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

  int get _selectedNavigationIndex => switch (selectedIndex) {
    0 => 0,
    1 => 1,
    2 => 3,
    3 => 4,
    _ => 0,
  };

  void _openVoice() {
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
  }

  void _selectDestination(int value) {
    if (value == 2) {
      _openVoice();
      return;
    }

    setState(() {
      selectedIndex = switch (value) {
        0 => 0,
        1 => 1,
        3 => 2,
        4 => 3,
        _ => selectedIndex,
      };
    });
  }

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
                AccountsScreen(),
                InsightsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavigationIndex,
        onDestinationSelected: _selectDestination,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(
            icon: Icon(Icons.list_rounded),
            label: "Activity",
          ),
          NavigationDestination(
            icon: _GastiNavigationIcon(),
            selectedIcon: _GastiNavigationIcon(),
            label: "Gasti",
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
    );
  }
}

class _GastiNavigationIcon extends StatelessWidget {
  const _GastiNavigationIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF21C4B6),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 38,
        child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 23),
      ),
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
