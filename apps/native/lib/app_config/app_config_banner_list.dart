import 'package:app/app_config/app_config_controller.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AppConfigBannerList extends StatelessWidget {
  const AppConfigBannerList({
    super.key,
    required this.placement,
    this.bottomSpacing = 0,
  });

  final String placement;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final banners = context.select<AppConfigController, List<AppConfigBanner>>(
      (config) => config.banners
          .where((banner) => banner.showsIn(placement))
          .toList(growable: false),
    );
    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final banner in banners) ...[
          _AppConfigBannerCard(banner: banner),
          if (banner != banners.last) const SizedBox(height: 12),
        ],
        if (bottomSpacing > 0) SizedBox(height: bottomSpacing),
      ],
    );
  }
}

class _AppConfigBannerCard extends StatelessWidget {
  const _AppConfigBannerCard({required this.banner});

  final AppConfigBanner banner;

  Future<void> _openAction(
    BuildContext context,
    AppConfigBannerAction action,
  ) async {
    final uri = Uri.tryParse(action.url);
    if (uri == null) {
      _showActionError(context);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) _showActionError(context);
  }

  void _showActionError(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.openLinkFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = _BannerPalette.forTone(colors, banner.tone);
    final title = switch (banner.fallback) {
      AppConfigBannerFallback.hardVersionUpdate =>
        context.l10n.updateRequiredTitle,
      AppConfigBannerFallback.softVersionUpdate =>
        context.l10n.updateAvailableTitle,
      null => banner.title,
    };
    final message = switch (banner.fallback) {
      AppConfigBannerFallback.hardVersionUpdate =>
        context.l10n.updateRequiredMessage,
      AppConfigBannerFallback.softVersionUpdate =>
        context.l10n.updateAvailableMessage,
      null => banner.messageMarkdown,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.iconBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(_iconForTone(banner.tone), color: palette.foreground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  MarkdownBody(
                    data: message,
                    onTapLink: (_, href, _) {
                      if (href == null) return;
                      _openAction(
                        context,
                        AppConfigBannerAction(label: href, url: href),
                      );
                    },
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.foreground,
                        height: 1.28,
                      ),
                      a: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.link,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                      strong: TextStyle(
                        color: palette.foreground,
                        fontWeight: FontWeight.w900,
                      ),
                      listBullet: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.foreground,
                      ),
                      blockSpacing: 6,
                    ),
                  ),
                  if (banner.actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in banner.actions)
                          FilledButton.tonalIcon(
                            onPressed: () => _openAction(context, action),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: Text(
                              banner.fallback ==
                                      AppConfigBannerFallback.softVersionUpdate
                                  ? context.l10n.updateApp
                                  : action.label,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForTone(String tone) {
  if (tone == 'critical') return Icons.system_update_rounded;
  if (tone == 'warning') return Icons.warning_amber_rounded;
  return Icons.info_outline_rounded;
}

class _BannerPalette {
  const _BannerPalette({
    required this.background,
    required this.border,
    required this.foreground,
    required this.iconBackground,
    required this.link,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final Color iconBackground;
  final Color link;

  static _BannerPalette forTone(ColorScheme colors, String tone) {
    if (tone == 'critical') {
      return _BannerPalette(
        background: colors.errorContainer,
        border: colors.error.withValues(alpha: 0.38),
        foreground: colors.onErrorContainer,
        iconBackground: colors.error.withValues(alpha: 0.18),
        link: colors.error,
      );
    }
    if (tone == 'warning') {
      return _BannerPalette(
        background: colors.tertiaryContainer,
        border: colors.tertiary.withValues(alpha: 0.38),
        foreground: colors.onTertiaryContainer,
        iconBackground: colors.tertiary.withValues(alpha: 0.18),
        link: colors.tertiary,
      );
    }
    return _BannerPalette(
      background: colors.secondaryContainer,
      border: colors.secondary.withValues(alpha: 0.34),
      foreground: colors.onSecondaryContainer,
      iconBackground: colors.secondary.withValues(alpha: 0.16),
      link: colors.secondary,
    );
  }
}
