import 'dart:async';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/bootstrap.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/account.dart';
import 'package:app/auth/pop_on_account_switch.dart';
import 'package:app/config.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/screens/accounts.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/home.dart';
import 'package:app/screens/insights.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/voice.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/voice/gemini_voice_expense_command.dart';
import 'package:app/voice/voice_session_remote_sync.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadAppConfig();

  const storage = FlutterSecureStorage();

  // L0: resolve the backend URL before the WS client is initialized. Fails
  // open — keeps the bundled/cached URL on any error.
  await resolveBackendConfig(storage);

  await ConvexClient.initialize(
    ConvexConfig(
      deploymentUrl: AppConfig.convexUrl,
      clientId: 'wallet-bot-flutter',
    ),
  );

  await GoogleSignIn.instance.initialize(
    serverClientId: AppConfig.googleServerClientId,
  );

  // Platform + app version, resolved once and shared by the config controller
  // and the sync engine so both gates identify the client the same way.
  final clientInfo = await ClientInfo.resolve(storage: storage);

  final auth = AuthController();
  await auth.load();

  // Native version verdict. Loaded in the background; sync waits for `loaded`,
  // while an offline start resolves fast from cache/bundled defaults.
  final appConfig = AppConfigController(
    clientInfo: clientInfo,
    storage: storage,
  );
  unawaited(appConfig.load());
  auth.addListener(() {
    unawaited(appConfig.loadAccount(auth.activeAccount));
  });
  unawaited(appConfig.loadAccount(auth.activeAccount));

  runApp(MyApp(auth: auth, appConfig: appConfig, clientInfo: clientInfo));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.appConfig,
    required this.clientInfo,
  });

  final AuthController auth;
  final AppConfigController appConfig;
  final ClientInfo clientInfo;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<AppConfigController>.value(value: appConfig),
        Provider<ClientInfo>.value(value: clientInfo),
      ],
      child: MaterialApp(
        title: 'Wallet Bot',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        ),
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
        Provider<VoiceSessionRepository>(
          create: (ctx) => VoiceSessionRepository(
            ctx.read<AppDatabase>(),
            remoteEnabled: active.type == AccountType.remote,
          ),
        ),
        if (active.type == AccountType.remote)
          Provider<VoiceSessionRemoteSync>(
            lazy: false,
            create: (ctx) {
              final sync = VoiceSessionRemoteSync(
                repository: ctx.read<VoiceSessionRepository>(),
                ownerId: active.id,
              );
              sync.schedule(delay: Duration.zero);
              return sync;
            },
            dispose: (_, sync) => unawaited(sync.dispose()),
          ),
        Provider<GeminiVoiceExpenseCommandFactory>(
          create: (ctx) => GeminiVoiceExpenseCommandFactory(
            repositories: ctx.read<AppRepositories>(),
            sessionRepository: ctx.read<VoiceSessionRepository>(),
            remoteSync: active.type == AccountType.remote
                ? ctx.read<VoiceSessionRemoteSync>()
                : null,
            useAuthenticatedTokenAction: active.type == AccountType.remote,
            sessionToken: active.sessionToken,
            convexSiteUrl: AppConfig.convexSiteUrl,
          ),
          dispose: (_, factory) => unawaited(factory.dispose()),
        ),
        // Drives the bottom-nav tab selection and lets one tab hand a filter to
        // another (e.g. an account's "Ver todas" opens Activity filtered to it).
        ChangeNotifierProvider<AppNavigation>(create: (_) => AppNavigation()),
        // SyncEngine only attaches for remote accounts. For local accounts
        // we still create one (so `Provider.of<SyncEngine>` is non-null
        // throughout the tree) but never call `.start()`, keeping it inert.
        ChangeNotifierProvider<SyncEngine>(
          create: (ctx) => SyncEngine(
            db: ctx.read<AppDatabase>(),
            client: ConvexClient.instance,
            clientInfo: ctx.read<ClientInfo>(),
            // Backstop for the client-side gate: if the server rejects this
            // client as outdated, reflect it so the hard update banner shows
            // and sync stays gated off.
            onClientOutdated: () =>
                ctx.read<AppConfigController>().markUnsupported(),
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
    final config = context.watch<AppConfigController>();
    final active = auth.activeAccount;
    if (!_kicked &&
        active != null &&
        active.sessionToken != null &&
        auth.convexAuthenticated &&
        config.loaded &&
        config.syncAllowed) {
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
  TransactionFilter _activityFilter = const TransactionFilter();
  int _activityFilterRevision = 0;

  void _openActivityWithFilter(TransactionFilter filter) {
    setState(() {
      _activityFilter = filter;
      _activityFilterRevision++;
    });
    context.read<AppNavigation>().index = 1;
  }

  @override
  Widget build(BuildContext context) {
    final needsReauth = context.select<AuthController, bool>(
      (a) => a.activeAccount?.requiresReauth ?? false,
    );
    final selectedIndex = context.watch<AppNavigation>().index;
    return Scaffold(
      body: Column(
        children: [
          if (needsReauth) const _ReauthBanner(),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                HomeScreen(onOpenActivity: _openActivityWithFilter),
                ActivityScreen(
                  initialFilter: _activityFilter,
                  filterRevision: _activityFilterRevision,
                ),
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
          final repositories = context.read<AppRepositories>();
          final commandFactory = context
              .read<GeminiVoiceExpenseCommandFactory>();
          final accountId = context.read<AuthController>().activeAccount?.id;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Provider<AppRepositories>.value(
                value: repositories,
                child: PopOnAccountSwitch(
                  accountId: accountId,
                  child: VoiceScreen(commandFactory: commandFactory),
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
        onDestinationSelected: (value) =>
            context.read<AppNavigation>().index = value,
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
                  } on GoogleSignInException catch (e) {
                    // Dismissing the Google sheet isn't a failure to report.
                    if (e.code != GoogleSignInExceptionCode.canceled) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('No se pudo reconectar: $e')),
                      );
                    }
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
