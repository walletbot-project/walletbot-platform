import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/pop_on_account_switch.dart';
import 'package:app/app_config/app_config_banner_list.dart';
import 'package:app/components/dashboard/add_widget_sheet.dart';
import 'package:app/components/dashboard/dashboard_section.dart';
import 'package:app/components/dashboard/default_dashboard.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/settings.dart';
import 'package:app/screens/transaction_form.dart';
import 'package:app/shared/app_navigation.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/sync/sync_status.dart';
import 'package:app/sync/sync_status_pill.dart';
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
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        final auth = dialogContext.watch<AuthController>();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.l10n.yourAccounts),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            body: ListView(
              children: [
                for (final account in auth.accounts)
                  ListTile(
                    leading: _AccountAvatar(account: account),
                    title: Text(
                      account.name ?? account.email ?? context.l10n.noName,
                    ),
                    subtitle: Text(
                      account.type == AccountType.local
                          ? context.l10n.localAccount
                          : account.email ?? context.l10n.syncedAccount,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (account.id == auth.activeId)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check_circle),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: context.l10n.removeAccount,
                          onPressed: () =>
                              _confirmRemoveAccount(dialogContext, account),
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (account.id != auth.activeId) {
                        await auth.switchTo(account.id);
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text(context.l10n.addAccount),
                  onTap: () {
                    final previousId = auth.activeId;
                    Navigator.pop(dialogContext);
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PopOnAccountSwitch(
                          accountId: previousId,
                          child: const LoginScreen(canDismiss: true),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: Text(context.l10n.settings),
                  onTap: () => Navigator.of(dialogContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRemoveAccount(
    BuildContext dialogContext,
    UserAccount account,
  ) async {
    final auth = dialogContext.read<AuthController>();
    final l10n = dialogContext.l10n;
    final label = account.name ?? account.email ?? context.l10n.thisAccount;
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmContext) => AlertDialog(
        title: Text(context.l10n.removeAccount),
        content: Text(context.l10n.removeAccountConfirmation(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final wasActive = account.id == auth.activeId;
    try {
      if (account.type == AccountType.local) {
        await auth.deleteLocal(account.id);
      } else {
        await auth.signOutRemote(account.id);
      }
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(SnackBar(content: Text(l10n.removeAccountFailed(e))));
      }
      return;
    }

    // Removing the active account drops us back to the login screen; close the
    // switcher so it is not left floating above it.
    if (wasActive && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
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
          Align(
            alignment: Alignment.centerLeft,
            child: _HomeActionCard(
              label: context.l10n.addManually,
              icon: Icons.add_rounded,
              onTap: _openManualAdd,
            ),
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
    return SizedBox.square(
      dimension: 112,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD3CCD8), width: 1.4),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF21C4B6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.black,
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

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final UserAccount account;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLocal = account.type == AccountType.local;
    final picture = account.picture;

    return CircleAvatar(
      radius: 20,
      backgroundColor: isLocal
          ? colors.secondaryContainer
          : colors.tertiaryContainer,
      foregroundColor: isLocal
          ? colors.onSecondaryContainer
          : colors.onTertiaryContainer,
      backgroundImage: picture == null ? null : NetworkImage(picture),
      child: picture == null
          ? Icon(isLocal ? Icons.person_outline : Icons.cloud_outlined)
          : null,
    );
  }
}
