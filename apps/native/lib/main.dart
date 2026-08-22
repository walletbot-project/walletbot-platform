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
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/accounts.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/home.dart';
import 'package:app/screens/insights.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/voice.dart';
import 'package:app/settings/display_settings.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/shared/breakpoints.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/telemetry/business_metrics.dart';
import 'package:app/telemetry/telemetry_client.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:app/voice/gemini_voice_expense_command.dart';
import 'package:app/voice/voice_session_remote_sync.dart';
import 'package:app/voice/voice_session_repository.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  // On web the client ID comes from the <meta name="google-signin-client_id">
  // tag in web/index.html, and serverClientId is not supported (the plugin
  // asserts it is null). A missing/invalid client ID must not prevent the app
  // from rendering — only sign-in becomes unavailable.
  try {
    await GoogleSignIn.instance.initialize(
      serverClientId: kIsWeb ? null : AppConfig.googleServerClientId,
    );
  } catch (e, st) {
    debugPrint('GoogleSignIn.initialize failed: $e\n$st');
  }

  // Platform + app version, resolved once and shared by the config controller
  // and the sync engine so both gates identify the client the same way.
  final clientInfo = await ClientInfo.resolve(storage: storage);

  final auth = AuthController();
  final displaySettings = DisplaySettingsController();
  await displaySettings.load();
  await auth.load();
  final telemetry = TelemetryClient(
    accessTokenProvider: auth.fetchAccessTokenForHttp,
  );

  // Native version verdict. Loaded in the background; sync waits for `loaded`,
  // while an offline start resolves fast from cache/bundled defaults.
  final appConfig = AppConfigController(
    clientInfo: clientInfo,
    storage: storage,
    locale: _resolvedLocaleTag(displaySettings),
  );
  unawaited(appConfig.load());
  auth.addListener(() {
    unawaited(appConfig.loadAccount(auth.activeAccount));
  });
  unawaited(appConfig.loadAccount(auth.activeAccount));

  runApp(
    MyApp(
      auth: auth,
      displaySettings: displaySettings,
      appConfig: appConfig,
      clientInfo: clientInfo,
      telemetry: telemetry,
    ),
  );
}

String _resolvedLocaleTag(DisplaySettingsController settings) =>
    (settings.locale ?? WidgetsBinding.instance.platformDispatcher.locale)
        .toLanguageTag();

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.displaySettings,
    required this.appConfig,
    required this.clientInfo,
    this.locale,
    this.telemetry,
  });

  final AuthController auth;
  final DisplaySettingsController displaySettings;
  final Locale? locale;
  final AppConfigController appConfig;
  final ClientInfo clientInfo;
  final TelemetryClient? telemetry;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.displaySettings.addListener(_refreshConfigLocale);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.displaySettings.language != DisplayLanguage.system) return;
    _refreshConfigLocale(
      systemLocale: locales == null || locales.isEmpty ? null : locales.first,
    );
  }

  void _refreshConfigLocale({Locale? systemLocale}) {
    final locale =
        widget.displaySettings.locale ??
        systemLocale ??
        WidgetsBinding.instance.platformDispatcher.locale;
    if (!widget.appConfig.updateLocale(locale.toLanguageTag())) return;
    unawaited(widget.appConfig.load());
    unawaited(widget.appConfig.loadAccount(widget.auth.activeAccount));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.displaySettings.removeListener(_refreshConfigLocale);
    widget.telemetry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: widget.auth),
        ChangeNotifierProvider<DisplaySettingsController>.value(
          value: widget.displaySettings,
        ),
        ChangeNotifierProvider<AppConfigController>.value(
          value: widget.appConfig,
        ),
        Provider<ClientInfo>.value(value: widget.clientInfo),
        if (widget.telemetry != null)
          Provider<TelemetryClient>.value(value: widget.telemetry!),
        if (widget.telemetry != null)
          Provider<BusinessMetrics>(
            create: (_) => BusinessMetrics(widget.telemetry!),
          ),
      ],
      child: _TelemetryStarter(
        child: Consumer<DisplaySettingsController>(
          builder: (context, settings, _) => MaterialApp(
            locale: widget.locale ?? settings.locale,
            onGenerateTitle: (context) => context.l10n.appTitle,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: settings.themeMode,
            home: const _AuthGate(),
          ),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6DE7D8),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return ThemeData(
      colorScheme: colorScheme,
      // Selected tab: neutral readable label with a turquoise underline
      // (primary at tone 40 reads green; the container keeps the brand hue).
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.primaryContainer,
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
      // Selected segment uses the bright brand container instead of the pale
      // secondaryContainer default, so selections read turquoise.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.primaryContainer
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : null,
          ),
        ),
      ),
      // Solid filled buttons use the bright brand turquoise (primaryContainer)
      // instead of the dark `primary` tone, which reads green in light mode.
      // Note: this also targets FilledButton.tonal, so tonal buttons that must
      // stay lower-emphasis set secondaryContainer explicitly at their call site.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
        ),
      ),
      timePickerTheme: const TimePickerThemeData(
        dialTextStyle: TextStyle(fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
    );
  }
}

class _TelemetryStarter extends StatefulWidget {
  const _TelemetryStarter({required this.child});

  final Widget child;

  @override
  State<_TelemetryStarter> createState() => _TelemetryStarterState();
}

class _TelemetryStarterState extends State<_TelemetryStarter> {
  bool _sent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sent) return;
    final telemetry = context.read<TelemetryClient?>();
    if (telemetry == null) return;
    _sent = true;
    unawaited(telemetry.track('app.started'));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final active = context.watch<AuthController>().activeAccount;
    if (active == null) return const LoginScreen();
    return MultiProvider(
      // Recreate account-scoped services when re-auth replaces the account
      // object, so factories never retain an obsolete session token. ObjectKey
      // avoids embedding the secret itself in diagnostic key output.
      key: ObjectKey(active),
      providers: [
        Provider<AppDatabase>(
          create: (_) => AppDatabase.forUser(active.id),
          dispose: (_, db) => db.close(),
        ),
        // The user's default currency. Scoped to the account subtree (like
        // AppDatabase above) so switching accounts never leaks a stale value.
        // Created for local accounts too (kept purely device-local, no
        // backend user exists to own the setting) so it's always available.
        ChangeNotifierProvider<DefaultCurrencyController>(
          create: (_) {
            final controller = DefaultCurrencyController(
              accountId: active.id,
              isRemote: active.type == AccountType.remote,
            );
            unawaited(controller.load());
            return controller;
          },
        ),
        // The app-facing data layer: all reads/writes from screens and the
        // voice agent go through this. Scoped to the account subtree so it is
        // recreated together with the database on account switch.
        Provider<AppRepositories>(
          create: (ctx) => AppRepositories(
            ctx.read<AppDatabase>(),
            businessMetrics: ctx.read<BusinessMetrics?>(),
            defaultCurrency: () => ctx.read<DefaultCurrencyController>().value,
          ),
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

  /// Keeps the four tab subtrees (and their scroll/edit State) alive when the
  /// shell flips between the bottom bar and the rail on window resize.
  final GlobalKey _tabStackKey = GlobalKey(debugLabel: 'appTabStack');

  void _openActivityWithFilter(TransactionFilter filter) {
    setState(() {
      _activityFilter = filter;
      _activityFilterRevision++;
    });
    context.read<AppNavigation>().index = 1;
  }

  void _openVoice() {
    // The voice route is pushed on the root navigator, above the
    // account-scoped providers: capture the active account's data layer
    // here, and dismiss the route if the account changes while open so
    // the agent can never write to a closed/foreign database.
    final repositories = context.read<AppRepositories>();
    final commandFactory = context.read<GeminiVoiceExpenseCommandFactory>();
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
  }

  @override
  Widget build(BuildContext context) {
    final needsReauth = context.select<AuthController, bool>(
      (a) => a.activeAccount?.requiresReauth ?? false,
    );
    // A deleted account is also `requiresReauth`, but offering "Reconnect"
    // there would sign the user into a brand-new empty account, so it gets its
    // own terminal banner.
    final serverDeleted = context.select<AuthController, bool>(
      (a) => a.activeAccount?.serverDeleted ?? false,
    );
    final selectedIndex = context.watch<AppNavigation>().index;
    final useRail = windowSizeClassOf(context) != WindowSizeClass.compact;

    // Built once per build and placed in exactly one branch below — never
    // both, or the GlobalKey would be duplicated within a single frame.
    final tabs = Column(
      children: [
        if (serverDeleted)
          const _AccountDeletedBanner()
        else if (needsReauth)
          const _ReauthBanner(),
        Expanded(
          child: IndexedStack(
            key: _tabStackKey,
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
    );

    return Scaffold(
      body: useRail
          ? Row(
              children: [
                _AgentCenteredRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) =>
                      context.read<AppNavigation>().index = value,
                  onOpenVoice: _openVoice,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: tabs),
              ],
            )
          : tabs,
      floatingActionButton: useRail
          ? null
          : FloatingActionButton(
              heroTag: 'voiceFab',
              onPressed: _openVoice,
              tooltip: context.l10n.voiceCommands,
              child: const _VoiceFabIcon(),
            ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (value) =>
                  context.read<AppNavigation>().index = value,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_rounded),
                  label: context.l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.calendar_view_month_rounded),
                  label: context.l10n.activity,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_balance_rounded),
                  label: context.l10n.accounts,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bookmarks_rounded),
                  label: context.l10n.insights,
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

/// Navigation rail whose voice-agent button sits between the second and third
/// destination, mirroring the centre-docked FAB of the compact bottom bar.
///
/// [NavigationRail] has no slot between destinations, so the four destinations
/// are split across two rails with the button in the gap. Both halves stay
/// top-aligned, like a single rail: the upper one is sized to its content with
/// [IntrinsicHeight] (a rail always fills the height it is given), the lower one
/// takes the remaining space. Both paint the same surface, and [IntrinsicWidth]
/// keeps the two halves the same width whatever the labels measure in the
/// active locale.
class _AgentCenteredRail extends StatelessWidget {
  const _AgentCenteredRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenVoice,
  });

  static const int _splitIndex = 2;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenVoice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IntrinsicWidth(
      child: Column(
        children: [
          IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selectedIndex < _splitIndex ? selectedIndex : null,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.home_rounded),
                  label: Text(l10n.home),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.calendar_view_month_rounded),
                  label: Text(l10n.activity),
                ),
              ],
            ),
          ),
          // 8 above + the destination's built-in 12 below it, 12 below + the
          // lower rail's 8 leading spacer: an even 20px gap on both sides.
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: FloatingActionButton(
              heroTag: 'voiceFab',
              elevation: 0,
              onPressed: onOpenVoice,
              tooltip: l10n.voiceCommands,
              child: const _VoiceFabIcon(),
            ),
          ),
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex >= _splitIndex
                  ? selectedIndex - _splitIndex
                  : null,
              onDestinationSelected: (value) =>
                  onDestinationSelected(value + _splitIndex),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.account_balance_rounded),
                  label: Text(l10n.accounts),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.bookmarks_rounded),
                  label: Text(l10n.insights),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The voice-agent FAB glyph: a speech bubble with a microphone overlapping its
/// lower-right corner, hinting at "talk to the assistant".
/// `apps/web/src/components/m3/agent-glyph.tsx` is the same drawing for web.
class _VoiceFabIcon extends StatelessWidget {
  const _VoiceFabIcon();

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    // The FAB hands its child an IconTheme carrying the foreground colour; SVG
    // has no such channel, so read it off the theme and tint with it. The
    // fallback is the FAB's own M3 default.
    final color =
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onPrimaryContainer;
    return SvgPicture.asset(
      'assets/agent-glyph.svg',
      width: _size,
      height: _size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Terminal state for an account deleted on the server. Unlike
/// [_ReauthBanner] it never offers to sign in again: the user id is gone, so a
/// fresh sign-in would create a *different* account with the same email rather
/// than restore this one. The local data stays readable offline until the user
/// explicitly removes it.
class _AccountDeletedBanner extends StatelessWidget {
  const _AccountDeletedBanner();

  Future<void> _confirmRemove(BuildContext context) async {
    final auth = context.read<AuthController>();
    final accountId = auth.activeAccount?.id;
    if (accountId == null) return;

    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.accountDeletedConfirmTitle),
        content: Text(l10n.accountDeletedConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.accountDeletedRemoveConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await auth.removeDeletedAccount(accountId);
  }

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
                Icons.person_off_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.accountDeletedBanner,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () => _confirmRemove(context),
                child: Text(context.l10n.accountDeletedRemove),
              ),
            ],
          ),
        ),
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
                  context.l10n.syncPaused,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l10n;
                  try {
                    await context.read<AuthController>().signInWithGoogle();
                  } on GoogleSignInException catch (e) {
                    // Dismissing the Google sheet isn't a failure to report.
                    if (e.code != GoogleSignInExceptionCode.canceled) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.reconnectFailed(e))),
                      );
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.reconnectFailed(e))),
                    );
                  }
                },
                child: Text(context.l10n.reconnect),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
