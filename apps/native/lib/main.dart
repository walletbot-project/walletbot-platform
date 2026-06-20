import 'dart:async';

import 'package:app/auth/auth_controller.dart';
import 'package:app/config.dart';
import 'package:app/data/data.dart';
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
        // The app-facing data layer: all reads/writes from screens and the
        // voice agent go through this. Scoped to the account subtree so it is
        // recreated together with the database on account switch.
        Provider<AppRepositories>(
          create: (ctx) => AppRepositories(ctx.read<AppDatabase>()),
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'voiceFab',
        onPressed: () {
          // The voice route is pushed on the root navigator, above the
          // account-scoped providers: capture the active account's data layer
          // here, and dismiss the route if the account changes while open so
          // the agent can never write to a closed/foreign database.
          final db = context.read<AppDatabase>();
          final repositories = context.read<AppRepositories>();
          final accountId = context.read<AuthController>().activeAccount?.id;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Provider<AppDatabase>.value(
                value: db,
                child: _PopOnAccountSwitch(
                  accountId: accountId,
                  child: VoiceScreen(
                    commandFactory: GeminiVoiceExpenseCommandFactory(
                      repositories: repositories,
                      convexSiteUrl: AppConfig.convexSiteUrl,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        tooltip: 'Voice commands',
        child: const Text('🤖'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_month_rounded),
            label: "Actividad",
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

/// Pops its route as soon as the active account is no longer the one the
/// route was opened for (switch, sign-out). The child captured account-scoped
/// objects at push time; once the account changes those are disposed, so the
/// route must not stay on screen.
class _PopOnAccountSwitch extends StatelessWidget {
  const _PopOnAccountSwitch({required this.accountId, required this.child});

  final String? accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final activeId = context.watch<AuthController>().activeAccount?.id;
    if (activeId != accountId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
      });
    }
    return child;
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
