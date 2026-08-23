import 'package:app/database.dart' show LegalDocumentKind;
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The two consent checks — 18+ and accepting the documents — plus a link to
/// each document being accepted.
///
/// Shared by the sign-up form, the local-account form and the acceptance gate,
/// so all three collect the same affirmative acceptance. Never pre-ticked:
/// showing the documents is not acceptance (docs/legal/README.md).
/// `apps/web/src/components/auth/legal-consent.tsx` is the web counterpart.
class LegalConsentChecks extends StatelessWidget {
  const LegalConsentChecks({
    super.key,
    required this.documents,
    required this.ageConfirmed,
    required this.accepted,
    required this.onAgeConfirmedChanged,
    required this.onAcceptedChanged,
    this.enabled = true,
  });

  /// What is being accepted right now: both documents on sign-up, and only the
  /// ones that actually changed at the gate — accepting a document nobody
  /// asked about would record consent that was never given.
  final List<LegalDocumentKind> documents;
  final bool ageConfirmed;
  final bool accepted;
  final ValueChanged<bool> onAgeConfirmedChanged;
  final ValueChanged<bool> onAcceptedChanged;
  final bool enabled;

  String _acceptLabel(AppLocalizations l10n) {
    if (documents.length > 1) return l10n.legalAcceptBoth;
    return documents.first == LegalDocumentKind.privacy
        ? l10n.legalAcceptPrivacy
        : l10n.legalAcceptTerms;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConsentCheck(
          value: ageConfirmed,
          label: l10n.legalAgeConfirm,
          onChanged: enabled ? onAgeConfirmedChanged : null,
        ),
        _ConsentCheck(
          value: accepted,
          label: _acceptLabel(l10n),
          onChanged: enabled ? onAcceptedChanged : null,
        ),
        const SizedBox(height: 4),
        for (final document in documents) _DocumentLink(document: document),
      ],
    );
  }
}

class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its own ink surface: the auth panel is a `DecoratedBox` with a
    // background, and a ListTile paints its splash on the nearest Material
    // ancestor — which would be *behind* that background. Flutter asserts on
    // exactly this, and the widget test caught it.
    return Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged == null
            ? null
            : (next) => onChanged!(next ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({required this.document});

  final LegalDocumentKind document;

  Future<void> _open(BuildContext context) async {
    final url = legalDocumentUrl(
      document,
      Localizations.localeOf(context).toLanguageTag(),
    );
    final uri = Uri.tryParse(url);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (uri == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.openLinkFailed)));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.openLinkFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = document == LegalDocumentKind.terms
        ? l10n.legalReadTerms
        : l10n.legalReadPrivacy;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => _open(context),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 36),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: Text(label),
      ),
    );
  }
}
