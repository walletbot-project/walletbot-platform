import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/components/grouped_card.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/settings/display_settings.dart';
import 'package:app/shared/adaptive_modal.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:app/widgets/currency_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<DisplaySettingsController>();
    final defaultCurrency = context.watch<DefaultCurrencyController>();
    final auth = context.watch<AuthController>();
    final active = auth.activeAccount;
    // User-account deletion only applies to server accounts with an email —
    // local accounts have no server-side data to delete.
    final deletableEmail = active != null && active.type == AccountType.remote
        ? active.email
        : null;
    final tileCount = deletableEmail != null ? 4 : 3;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PreferenceTile(
            icon: Icons.language_rounded,
            title: context.l10n.language,
            value: _languageLabel(context, settings.language),
            borderRadius: groupedRadius(0, tileCount),
            onTap: () => _showLanguageChoices(context, settings),
          ),
          const SizedBox(height: kGroupSpacing),
          _PreferenceTile(
            icon: Icons.palette_outlined,
            title: context.l10n.theme,
            value: _themeLabel(context, settings.theme),
            borderRadius: groupedRadius(1, tileCount),
            onTap: () => _showThemeChoices(context, settings),
          ),
          const SizedBox(height: kGroupSpacing),
          _PreferenceTile(
            icon: Icons.attach_money_rounded,
            title: context.l10n.currency,
            value: defaultCurrency.value,
            borderRadius: groupedRadius(2, tileCount),
            onTap: () => _showCurrencyChoices(context, defaultCurrency),
          ),
          if (deletableEmail != null) ...[
            const SizedBox(height: kGroupSpacing),
            _PreferenceTile(
              icon: Icons.person_off_rounded,
              title: context.l10n.deleteUserAccount,
              value: context.l10n.deleteUserAccountDescription,
              borderRadius: groupedRadius(3, tileCount),
              destructive: true,
              onTap: () =>
                  _confirmDeleteUserAccount(context, auth, deletableEmail),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDeleteUserAccount(
    BuildContext context,
    AuthController auth,
    String email,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteUserAccountConfirmTitle),
        content: Text(context.l10n.deleteUserAccountConfirmBody(email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.deleteUserAccountSend),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await auth.requestAccountDeletion(email: email);
      // Reached only when the deletion email really went out. The endpoint
      // used to answer the same 200 when it was throttled, when the account
      // was already deleted, and when the send itself failed — so this
      // snackbar claimed a link that had gone nowhere.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.deleteUserAccountEmailSent)),
      );
    } catch (err) {
      // Keep the forensic trail: the snackbar names the outcome, not the
      // underlying error.
      debugPrint('requestAccountDeletion failed: $err');
      if (!context.mounted) return;
      final l10n = context.l10n;
      final code = err is AuthHttpError ? err.code : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (code) {
            'account_not_found' => l10n.accountNotFoundForEmail(email),
            'account_already_deleted' => l10n.deleteUserAccountAlreadyDeleted,
            'rate_limited' => l10n.deleteUserAccountRateLimited,
            _ => l10n.deleteUserAccountFailed,
          }),
        ),
      );
    }
  }

  Future<void> _showLanguageChoices(
    BuildContext context,
    DisplaySettingsController settings,
  ) {
    return showAdaptiveModal<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SelectionSheet<DisplayLanguage>(
        title: context.l10n.language,
        description: context.l10n.languageDescription,
        selected: settings.language,
        choices: [
          _SettingsChoice(
            value: DisplayLanguage.system,
            icon: Icons.settings_suggest_rounded,
            label: context.l10n.systemDefault,
          ),
          _SettingsChoice(
            value: DisplayLanguage.english,
            icon: Icons.language_rounded,
            label: context.l10n.english,
          ),
          _SettingsChoice(
            value: DisplayLanguage.spanish,
            icon: Icons.language_rounded,
            label: context.l10n.spanish,
          ),
        ]..sort((a, b) => a.label.compareTo(b.label)),
        onSelected: (language) async {
          final saved = await _setLanguage(context, settings, language);
          if (saved && sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Future<void> _showThemeChoices(
    BuildContext context,
    DisplaySettingsController settings,
  ) {
    return showAdaptiveModal<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SelectionSheet<DisplayTheme>(
        title: context.l10n.theme,
        description: context.l10n.themeDescription,
        selected: settings.theme,
        choices: [
          _SettingsChoice(
            value: DisplayTheme.system,
            icon: Icons.brightness_auto_rounded,
            label: context.l10n.systemDefault,
          ),
          _SettingsChoice(
            value: DisplayTheme.light,
            icon: Icons.light_mode_rounded,
            label: context.l10n.lightTheme,
          ),
          _SettingsChoice(
            value: DisplayTheme.dark,
            icon: Icons.dark_mode_rounded,
            label: context.l10n.darkTheme,
          ),
        ],
        onSelected: (theme) async {
          final saved = await _setTheme(context, settings, theme);
          if (saved && sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Future<void> _showCurrencyChoices(
    BuildContext context,
    DefaultCurrencyController defaultCurrency,
  ) async {
    final picked = await showAdaptiveModal<String>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CurrencyPicker(selected: defaultCurrency.value),
    );
    if (picked == null) return;
    try {
      await defaultCurrency.setValue(picked);
    } catch (_) {
      if (context.mounted) _showSaveError(context);
    }
  }

  String _languageLabel(BuildContext context, DisplayLanguage language) =>
      switch (language) {
        DisplayLanguage.system => context.l10n.systemDefault,
        DisplayLanguage.english => context.l10n.english,
        DisplayLanguage.spanish => context.l10n.spanish,
      };

  String _themeLabel(BuildContext context, DisplayTheme theme) =>
      switch (theme) {
        DisplayTheme.system => context.l10n.systemDefault,
        DisplayTheme.light => context.l10n.lightTheme,
        DisplayTheme.dark => context.l10n.darkTheme,
      };

  Future<bool> _setLanguage(
    BuildContext context,
    DisplaySettingsController settings,
    DisplayLanguage language,
  ) async {
    try {
      await settings.setLanguage(language);
      return true;
    } catch (_) {
      if (context.mounted) _showSaveError(context);
      return false;
    }
  }

  Future<bool> _setTheme(
    BuildContext context,
    DisplaySettingsController settings,
    DisplayTheme theme,
  ) async {
    try {
      await settings.setTheme(theme);
      return true;
    } catch (_) {
      if (context.mounted) _showSaveError(context);
      return false;
    }
  }

  void _showSaveError(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaveFailed)));
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.borderRadius,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final BorderRadius borderRadius;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      color: destructive ? colors.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
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

class _SettingsChoice<T> {
  const _SettingsChoice({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

class _SelectionSheet<T> extends StatelessWidget {
  const _SelectionSheet({
    required this.title,
    required this.description,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String title;
  final String description;
  final T selected;
  final List<_SettingsChoice<T>> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                description,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < choices.length; i++) ...[
              _SelectionTile<T>(
                choice: choices[i],
                selected: choices[i].value == selected,
                borderRadius: groupedRadius(i, choices.length),
                onTap: () => onSelected(choices[i].value),
              ),
              if (i != choices.length - 1)
                const SizedBox(height: kGroupSpacing),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectionTile<T> extends StatelessWidget {
  const _SelectionTile({
    required this.choice,
    required this.selected,
    required this.borderRadius,
    required this.onTap,
  });

  final _SettingsChoice<T> choice;
  final bool selected;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GroupedCard(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              choice.icon,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                choice.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: selected ? colors.primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: colors.primary),
          ],
        ),
      ),
    );
  }
}
