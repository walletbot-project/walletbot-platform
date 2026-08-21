import 'dart:async';

import 'package:app/l10n/l10n.dart';
import 'package:app/legal/terms_acceptance.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The affirmative-acceptance row for the legal documents: one combined
/// checkbox covering the 18+ requirement and both documents, the document
/// names linking to the published pages in the active locale
/// (docs/legal/README.md, implementation TODO #8). Same sentence and links
/// as the web `TermsCheckbox` (apps/web/src/components/auth/terms-checkbox.tsx).
class TermsAcceptanceCheckbox extends StatefulWidget {
  const TermsAcceptanceCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  State<TermsAcceptanceCheckbox> createState() =>
      _TermsAcceptanceCheckboxState();
}

class _TermsAcceptanceCheckboxState extends State<TermsAcceptanceCheckbox> {
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => _openLegalPage(legalTermsUrl(context.localeName));
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => _openLegalPage(legalPrivacyUrl(context.localeName));

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openLegalPage(String url) {
    unawaited(
      launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ).catchError((Object e) {
        debugPrint('terms: could not open $url: $e');
        return false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final linkStyle = TextStyle(
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      color: colors.onSurface,
    );

    return Row(
      children: [
        Checkbox(
          value: widget.value,
          onChanged: widget.enabled
              ? (checked) => widget.onChanged(checked ?? false)
              : null,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                height: 1.3,
              ),
              children: [
                TextSpan(text: l10n.termsAge18Prefix),
                TextSpan(
                  text: l10n.termsLinkLabel,
                  style: linkStyle,
                  recognizer: _termsTap,
                ),
                TextSpan(text: l10n.termsAnd),
                TextSpan(
                  text: l10n.privacyLinkLabel,
                  style: linkStyle,
                  recognizer: _privacyTap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
