import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/pop_on_account_switch.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:app/screens/login.dart';
import 'package:app/screens/settings.dart';
import 'package:app/screens/whatsapp_link.dart';
import 'package:app/settings/display_settings.dart';
import 'package:app/sync/unsynced.dart';
import 'package:app/whatsapp/whatsapp_link_controller.dart' show kWhatsappFlag;
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens the account switcher as a full-screen dialog on the root navigator.
///
/// The route outlives the widget that opened it: switching accounts rekeys
/// `_AuthGate`'s subtree, so `HomeScreen` — and every other account-scoped
/// widget — is unmounted while this dialog is still on screen. The dialog is
/// also rebuilt by that very notification, because [AccountSwitcherView]
/// watches [AuthController]. It must therefore never read the calling
/// widget's `State.context`: doing so threw "This widget has been unmounted,
/// so the State no longer has a context" mid-build and painted a full-screen
/// red error widget over the app until the route came off.
///
/// [defaultCurrency] and [database] are account-scoped and live *below* this
/// route, so they are captured by value: the first for [SettingsScreen], the
/// second to check the active account for unpushed writes without opening a
/// second connection to a file that is already open.
Future<void> showAccountSwitcher(
  BuildContext context, {
  required DefaultCurrencyController defaultCurrency,
  required AppDatabase database,
}) {
  final openedForId = context.read<AuthController>().activeId;
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) => PopOnAccountSwitch(
      // Any change of active account — switching, removing this one, a
      // background token refresh finding it deleted — takes the switcher off
      // with it, so it never floats above a tree it no longer describes.
      accountId: openedForId,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(dialogContext.l10n.yourAccounts),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          body: AccountSwitcherView(
            defaultCurrency: defaultCurrency,
            database: database,
          ),
        ),
      ),
    ),
  );
}

/// The switcher's content: the active account and the actions that act on it,
/// then the other accounts on this device, then "add account".
///
/// Presented two ways, which is why it is a widget rather than a builder
/// closure: inside [showAccountSwitcher]'s dialog while an account is active,
/// and as [AccountChooserScreen] when none is.
class AccountSwitcherView extends StatelessWidget {
  const AccountSwitcherView({
    super.key,
    this.defaultCurrency,
    this.database,
    this.header,
  });

  /// The active account's currency controller, needed to push
  /// [SettingsScreen] from a route that sits above the account-scoped
  /// providers. Null when no account is active — which is also when there is
  /// no current-account group to put Settings in.
  final DefaultCurrencyController? defaultCurrency;

  /// The active account's open database, used only to look for unpushed
  /// writes before signing out of it. Null when no account is active.
  final AppDatabase? database;

  /// Optional intro placed above the groups, inside the same scroll view.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l10n = context.l10n;
    final active = auth.activeAccount;
    final others = [
      for (final account in auth.accounts)
        if (account.id != active?.id) account,
    ];

    // The current-account group: identity, Settings (only reachable with the
    // account-scoped controller in hand), WhatsApp (only for accounts in that
    // rollout), then the destructive action — whose name depends on what it
    // really does to this account.
    //
    // The config controller is read nullably because this view also builds
    // before the first config call lands, and in widget tests that never make
    // one; an unfetched flag reads false, so a feature nobody has been given
    // is never advertised.
    final currency = defaultCurrency;
    final whatsapp =
        context.watch<AppConfigController?>()?.isFlagEnabled(kWhatsappFlag) ??
        false;
    final topCount = (currency == null ? 2 : 3) + (whatsapp ? 1 : 0);

    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ?header,
          if (active != null) ...[
            _SectionLabel(l10n.currentAccount),
            _AccountCard(
              account: active,
              borderRadius: groupedRadius(0, topCount),
            ),
            if (currency != null) ...[
              const SizedBox(height: kGroupSpacing),
              _ActionTile(
                icon: Icons.settings_rounded,
                title: l10n.settings,
                borderRadius: groupedRadius(1, topCount),
                onTap: () => _openSettings(context, currency),
              ),
            ],
            if (whatsapp) ...[
              const SizedBox(height: kGroupSpacing),
              _ActionTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: l10n.whatsappTitle,
                borderRadius: groupedRadius(topCount - 2, topCount),
                onTap: () => _openWhatsapp(context, active),
              ),
            ],
            const SizedBox(height: kGroupSpacing),
            _ActionTile(
              icon: removalActionIcon(active),
              title: removalActionLabel(l10n, active),
              destructive: true,
              borderRadius: groupedRadius(topCount - 1, topCount),
              onTap: () =>
                  confirmRemoveAccount(context, active, openDatabase: database),
            ),
            const SizedBox(height: 24),
          ],
          if (others.isNotEmpty) ...[
            _SectionLabel(l10n.otherAccounts),
            for (var i = 0; i < others.length; i++) ...[
              _AccountCard(
                account: others[i],
                borderRadius: groupedRadius(i, others.length),
                onTap: () => _switchTo(context, others[i]),
                onRemove: () => confirmRemoveAccount(context, others[i]),
              ),
              if (i != others.length - 1) const SizedBox(height: kGroupSpacing),
            ],
            const SizedBox(height: 24),
          ],
          _ActionTile(
            icon: Icons.person_add_alt_1_rounded,
            title: l10n.addAccount,
            borderRadius: groupedRadius(0, 1),
            onTap: () => _openAddAccount(context, active?.id),
          ),
        ],
      ),
    );
  }

  void _switchTo(BuildContext context, UserAccount account) {
    // The switcher does not close itself: the [PopOnAccountSwitch] wrapping
    // whichever surface is showing it reacts to the same notification.
    context.read<AuthController>().switchTo(account.id);
  }

  void _openSettings(BuildContext context, DefaultCurrencyController currency) {
    final accountId = context.read<AuthController>().activeId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // `currency` belongs to the account that was active at push time and
        // is disposed when that changes; the screen watching it would throw.
        builder: (_) => PopOnAccountSwitch(
          accountId: accountId,
          child: ChangeNotifierProvider<DefaultCurrencyController>.value(
            value: currency,
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
  }

  void _openWhatsapp(BuildContext context, UserAccount account) {
    // The screen owns its own controller and caches nothing, so unlike
    // Settings there is no account-scoped controller to re-provide — only the
    // connection it would make its calls on, which lives below this route.
    // A local account has no backend user, and the screen says so instead of
    // offering a button that would fail.
    final client = context.read<ConvexClient?>();
    // Built here rather than read from the tree: the AI-consent controller is
    // account-scoped and lives below this route, while everything it needs
    // (ClientInfo, DisplaySettingsController, ConvexClient) is provided above
    // the MaterialApp. Both reads are nullable only for widget tests that
    // mount the switcher on a bare harness; in the app they always resolve,
    // and a null one means the screen runs without the gate exactly as a
    // non-iOS build does.
    final clientInfo = context.read<ClientInfo?>();
    final displaySettings = context.read<DisplaySettingsController?>();
    final aiConsent = clientInfo == null || displaySettings == null
        ? null
        : AiConsentController(
            accountId: account.id,
            isRemote: account.type == AccountType.remote,
            clientInfo: clientInfo,
            locale: displaySettings.localeTag,
            client: client,
          );
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PopOnAccountSwitch(
              accountId: account.id,
              child: WhatsappLinkScreen(
                isRemote: account.type == AccountType.remote,
                client: client,
                aiConsent: aiConsent,
              ),
            ),
          ),
        )
        .whenComplete(() => aiConsent?.dispose());
  }

  void _openAddAccount(BuildContext context, String? activeId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PopOnAccountSwitch(
          accountId: activeId,
          child: const LoginScreen(canDismiss: true),
        ),
      ),
    );
  }
}

/// Full-screen variant, shown by `_AuthGate` when no account is active but the
/// device still holds some — the state left behind by signing out of, or
/// removing, the account you were on. Sign-in stays one tap away under "add
/// account"; it is no longer the only way back in.
class AccountChooserScreen extends StatelessWidget {
  const AccountChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.yourAccounts)),
      body: AccountSwitcherView(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          child: Text(
            context.l10n.chooseAccountToContinue,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirms, then removes [account] and its local database from this device.
///
/// Three different things wear this one button, and the confirmation says
/// which: deleting a local account destroys the only copy of its data; signing
/// out of a remote account leaves the server copy intact; removing an account
/// the server has already deleted is neither. The remote case additionally
/// warns when the engine still holds unpushed writes, because those *are* lost
/// — the guard the `signOutRemote` TODO asked for once sync existed.
///
/// [openDatabase] must be the active account's already-open database, and only
/// ever for that account — opening a second connection to the same file races
/// the first. Other accounts are read through a short-lived connection.
Future<void> confirmRemoveAccount(
  BuildContext context,
  UserAccount account, {
  AppDatabase? openDatabase,
}) async {
  final auth = context.read<AuthController>();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final isLocal = account.type == AccountType.local;
  final label = account.name ?? account.email ?? l10n.thisAccount;

  // A server-deleted account can never sync again, so there is nothing to warn
  // about; a local one was never syncing in the first place.
  final unsynced = isLocal || account.serverDeleted
      ? false
      : await _hasUnsyncedWork(account, openDatabase);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (confirmContext) {
      final theme = Theme.of(confirmContext);
      return AlertDialog(
        title: Text(
          account.serverDeleted
              ? l10n.accountDeletedConfirmTitle
              : isLocal
              ? l10n.deleteLocalAccountConfirmTitle(label)
              : l10n.signOutConfirmTitle(label),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.serverDeleted
                  ? l10n.accountDeletedConfirmBody
                  : isLocal
                  ? l10n.deleteLocalAccountConfirmBody
                  : l10n.signOutConfirmBody,
            ),
            if (unsynced) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sync_problem_rounded,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.signOutUnsyncedWarning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: Text(
              account.serverDeleted
                  ? l10n.remove
                  : isLocal
                  ? l10n.delete
                  : l10n.signOut,
            ),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;

  try {
    if (isLocal) {
      await auth.deleteLocal(account.id);
    } else {
      await auth.signOutRemote(account.id);
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.removeAccountFailed(e))),
    );
  }
}

Future<bool> _hasUnsyncedWork(
  UserAccount account,
  AppDatabase? openDatabase,
) async {
  try {
    if (openDatabase != null) return await hasUnsyncedChanges(openDatabase);
    final db = AppDatabase.forUser(account.id);
    try {
      return await hasUnsyncedChanges(db);
    } finally {
      await db.close();
    }
  } catch (e) {
    // Can't tell — say so rather than stay quiet. This confirmation is the
    // last thing standing between the user and an irreversible delete.
    debugPrint('accountSwitcher: unsynced check failed: $e');
    return true;
  }
}

/// What the destructive action on [account] is called: the three cases of
/// [confirmRemoveAccount], named the same way in the tile, its tooltip, and
/// the confirmation's button.
String removalActionLabel(AppLocalizations l10n, UserAccount account) {
  if (account.serverDeleted) return l10n.removeAccount;
  return account.type == AccountType.local
      ? l10n.deleteLocalAccount
      : l10n.signOut;
}

IconData removalActionIcon(UserAccount account) =>
    account.type == AccountType.local || account.serverDeleted
    ? Icons.delete_outline_rounded
    : Icons.logout_rounded;

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One account as a grouped card: avatar, name, and what kind of account it
/// is. [onTap] switches to it; [onRemove] adds the trailing remove button.
/// The active account's card has neither — it is already active, and its
/// removal is a row of its own in the group below it.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.borderRadius,
    this.onTap,
    this.onRemove,
  });

  final UserAccount account;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;

    // A deleted account stays in the list — its local data is still readable
    // offline — so the row has to say why it will never sync again.
    final subtitle = account.serverDeleted
        ? l10n.accountDeletedBanner
        : account.type == AccountType.local
        ? l10n.localAccount
        : account.email ?? l10n.syncedAccount;

    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, onRemove == null ? 16 : 4, 12),
        child: Row(
          children: [
            _AccountAvatar(account: account),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name ?? account.email ?? l10n.noName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: account.serverDeleted ? colors.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: account.serverDeleted
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: Icon(removalActionIcon(account)),
                tooltip: removalActionLabel(l10n, account),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// A grouped-card row that performs an action, matching the settings screen's
/// preference tiles.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.borderRadius,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final BorderRadius borderRadius;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: destructive
                    ? colors.errorContainer
                    : colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 22,
                color: destructive
                    ? colors.onErrorContainer
                    : colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: destructive ? colors.error : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
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

    // A deleted account drops its photo on purpose: a familiar face reads as a
    // working account, which is the one thing this row must not look like.
    if (account.serverDeleted) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.errorContainer,
        foregroundColor: colors.onErrorContainer,
        child: const Icon(Icons.person_off_rounded),
      );
    }

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
