import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _glyphAsset = 'assets/agent-glyph.svg';

/// Home invitation to try the assistant. Only the close button hides it for
/// good; the dismissal is device-scoped, so it lives in SharedPreferences
/// rather than the per-user database.
class AssistantBanner extends StatefulWidget {
  const AssistantBanner({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<AssistantBanner> createState() => _AssistantBannerState();
}

class _AssistantBannerState extends State<AssistantBanner> {
  static const _dismissedKey = 'assistant_banner_dismissed';

  final _preferences = SharedPreferencesAsync();

  // Null until the stored dismissal is read, so a dismissed banner never
  // flashes on screen while loading.
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    _preferences
        .getBool(_dismissedKey)
        .then(
          (value) {
            if (mounted) setState(() => _dismissed = value ?? false);
          },
          onError: (Object e) {
            debugPrint('assistant banner: reading dismissal failed: $e');
            if (mounted) setState(() => _dismissed = false);
          },
        );
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    _preferences.setBool(_dismissedKey, true).catchError((Object e) {
      debugPrint('assistant banner: saving dismissal failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed != false) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ink = colors.onPrimaryContainer;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: colors.primaryContainer,
          child: Stack(
            children: [
              Positioned(
                top: -70,
                right: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 36),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ink,
                              shape: BoxShape.circle,
                            ),
                            child: SvgPicture.asset(
                              _glyphAsset,
                              width: 24,
                              height: 24,
                              colorFilter: ColorFilter.mode(
                                colors.primaryContainer,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.assistantBannerTitle,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MessageBubble(text: l10n.assistantBannerMessage, ink: ink),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: widget.onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(l10n.assistantBannerAction),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 18,
                right: 8,
                child: IconButton(
                  tooltip: l10n.close,
                  onPressed: _dismiss,
                  color: ink,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 18, color: ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
