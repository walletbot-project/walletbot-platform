import 'package:app/components/grouped_card.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/settings/display_settings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<DisplaySettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PreferenceTile(
            icon: Icons.language_rounded,
            title: context.l10n.language,
            value: _languageLabel(context, settings.language),
            borderRadius: groupedRadius(0, 2),
            onTap: () => _showLanguageChoices(context, settings),
          ),
          const SizedBox(height: kGroupSpacing),
          _PreferenceTile(
            icon: Icons.palette_outlined,
            title: context.l10n.theme,
            value: _themeLabel(context, settings.theme),
            borderRadius: groupedRadius(1, 2),
            onTap: () => _showThemeChoices(context, settings),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageChoices(
    BuildContext context,
    DisplaySettingsController settings,
  ) {
    return showModalBottomSheet<void>(
      context: context,
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
    return showModalBottomSheet<void>(
      context: context,
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
  });

  final IconData icon;
  final String title;
  final String value;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

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
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
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
