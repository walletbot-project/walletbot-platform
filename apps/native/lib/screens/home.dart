import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/app_config/app_config_banner_list.dart';
import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/feedback/feedback_sheet.dart';
import 'package:app/components/dashboard/dashboard_section.dart';
import 'package:app/components/dashboard/default_dashboard.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/account_switcher.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/sync/sync_status.dart';
import 'package:app/sync/sync_status_pill.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenActivity});

  final ValueChanged<TransactionFilter> onOpenActivity;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _seedInFlight = false;
  bool _seedFinished = false;
  bool _remoteSeedScheduled = false;
  SyncEngine? _syncEngine;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = context.read<AuthController>().activeAccount;
    if (active?.type == AccountType.local) {
      _detachSyncListener();
      _maybeSeedDashboard(respectDeleteHistory: false);
      return;
    }

    final engine = context.read<SyncEngine>();
    if (!identical(_syncEngine, engine)) {
      _detachSyncListener();
      _syncEngine = engine..addListener(_onSyncChanged);
    }
    _onSyncChanged();
  }

  /// Remote dashboards must finish their first pull before the local empty-table
  /// check. Otherwise defaults and an existing remote layout are merged into one
  /// invalid grid. Local-only accounts can seed immediately.
  void _onSyncChanged() {
    if (_syncEngine?.status != SyncStatus.synced ||
        _seedFinished ||
        _seedInFlight ||
        _remoteSeedScheduled) {
      return;
    }
    // SyncStatus.synced is published just before the cycle's in-flight future
    // clears. Wait until the next frame so seed writes are observed as new local
    // work and schedule their own push.
    _remoteSeedScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _remoteSeedScheduled = false;
      if (!mounted || _syncEngine?.status != SyncStatus.synced) return;
      _maybeSeedDashboard(respectDeleteHistory: true);
    });
  }

  void _maybeSeedDashboard({required bool respectDeleteHistory}) {
    if (_seedFinished || _seedInFlight) return;
    _seedInFlight = true;
    final repos = context.read<AppRepositories>();
    final l10n = context.l10n;
    repos.dashboard
        .seedDefaultIfEmpty(
          () => writeDefaultDashboardSeed(repos, l10n),
          respectDeleteHistory: respectDeleteHistory,
        )
        .then((_) {
          _seedInFlight = false;
          _seedFinished = true;
        })
        .catchError((Object e, StackTrace st) {
          _seedInFlight = false;
          debugPrint('home: default dashboard seed failed: $e');
        });
  }

  void _detachSyncListener() {
    _syncEngine?.removeListener(_onSyncChanged);
    _syncEngine = null;
  }

  @override
  void dispose() {
    _detachSyncListener();
    super.dispose();
  }

  void showUserMenu() {
    // Everything the switcher needs is handed over by value: its route lives
    // above the account-scoped providers and outlives this State, which the
    // next account switch unmounts. See `showAccountSwitcher`.
    showAccountSwitcher(
      context,
      defaultCurrency: context.read<DefaultCurrencyController>(),
      database: context.read<AppDatabase>(),
    );
  }

  Future<void> _openManualAdd() async {
    // Pushed routes sit above the account-scoped providers; re-provide them
    // so the new route keeps using the active account's data layer.
    final repos = context.read<AppRepositories>();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Provider<AppRepositories>.value(
          value: repos,
          child: const TransactionFormScreen(),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    context.read<AppNavigation>().index = AppNavigation.activityTab;
  }

  bool _editing = false;

  Future<void> _openAddWidget() async {
    final repos = context.read<AppRepositories>();
    await showAddWidgetSheet(context, repos);
  }

  Future<void> _openFeedback() async {
    await showFeedbackSheet(
      context,
      clientInfo: context.read<ClientInfo>(),
      locale: context.read<AppConfigController>().locale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.home),
        actions: _editing
            ? [
                IconButton(
                  tooltip: context.l10n.addWidget,
                  onPressed: _openAddWidget,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: context.l10n.done,
                  onPressed: () => setState(() => _editing = false),
                  icon: const Icon(Icons.check_rounded),
                ),
              ]
            : [
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Center(child: SyncStatusPill()),
                ),
                IconButton(
                  tooltip: context.l10n.editDashboard,
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: showUserMenu,
                  icon: const Icon(Icons.person_rounded),
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppConfigBannerList(placement: 'home', bottomSpacing: 16),
          DashboardSection(
            editing: _editing,
            onStartEditing: () => setState(() => _editing = true),
            onOpenFilter: widget.onOpenActivity,
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.actions,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HomeActionCard(
                label: context.l10n.addManually,
                icon: Icons.add_rounded,
                onTap: _openManualAdd,
              ),
              if (context.watch<AppConfigController>().isFlagEnabled(
                'feedback',
              ))
                _HomeActionCard(
                  label: context.l10n.sendFeedback,
                  icon: Icons.feedback_rounded,
                  onTap: _openFeedback,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox.square(
      dimension: 112,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant, width: 1.4),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer, size: 30),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
