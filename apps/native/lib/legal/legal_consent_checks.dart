import 'package:app/database.dart' show LegalDocumentKind;
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The two consent checks: 18+ and accepting the documents, each document
/// named as a link to its published text.
///
/// Shared by the sign-up form and the acceptance gate, so both collect the same
/// affirmative acceptance. Never pre-ticked: showing the documents is not
/// acceptance (docs/legal/README.md).
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

  String _acceptTemplate(AppLocalizations l10n) {
    if (documents.length > 1) return l10n.legalAcceptBoth;
    return documents.first == LegalDocumentKind.privacy
        ? l10n.legalAcceptPrivacy
        : l10n.legalAcceptTerms;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConsentCheck(
          value: ageConfirmed,
          label: Text(l10n.legalAgeConfirm, style: style),
          onChanged: enabled ? onAgeConfirmedChanged : null,
        ),
        _ConsentCheck(
          value: accepted,
          label: _ConsentLabel(template: _acceptTemplate(l10n), style: style),
          onChanged: enabled ? onAcceptedChanged : null,
        ),
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
  final Widget label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
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
        title: label,
      ),
    );
  }
}

/// One segment of an accept template: literal text, or a document link.
@immutable
class _LabelSegment {
  const _LabelSegment.text(this.text) : document = null;
  const _LabelSegment.link(this.document) : text = '';

  final String text;
  final LegalDocumentKind? document;
}

/// `[[terms]]` / `[[privacy]]`, as written in the ARB files.
final _documentMarker = RegExp(r'\[\[(terms|privacy)\]\]');

List<_LabelSegment> _parseTemplate(String template) {
  final segments = <_LabelSegment>[];
  var index = 0;
  for (final match in _documentMarker.allMatches(template)) {
    if (match.start > index) {
      segments.add(_LabelSegment.text(template.substring(index, match.start)));
    }
    segments.add(
      _LabelSegment.link(
        match.group(1) == 'terms'
            ? LegalDocumentKind.terms
            : LegalDocumentKind.privacy,
      ),
    );
    index = match.end;
  }
  if (index < template.length) {
    segments.add(_LabelSegment.text(template.substring(index)));
  }
  return segments;
}

/// The accept label with each document name as a tappable link.
///
/// The links live inside the sentence rather than in a list under it: the panel
/// is short, and a separate "read X" row per document cost two lines. The ARB
/// keeps the marker form so each language can place the names — and its own
/// articles — where they belong.
class _ConsentLabel extends StatefulWidget {
  const _ConsentLabel({required this.template, required this.style});

  final String template;
  final TextStyle? style;

  @override
  State<_ConsentLabel> createState() => _ConsentLabelState();
}

class _ConsentLabelState extends State<_ConsentLabel> {
  late List<_LabelSegment> _segments;
  final Map<LegalDocumentKind, TapGestureRecognizer> _recognizers = {};

  @override
  void initState() {
    super.initState();
    _buildSegments();
  }

  @override
  void didUpdateWidget(_ConsentLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) _buildSegments();
  }

  void _buildSegments() {
    _segments = _parseTemplate(widget.template);
    for (final segment in _segments) {
      final document = segment.document;
      if (document == null || _recognizers.containsKey(document)) continue;
      // The recognizer wins the tap over the enclosing tile, so opening a
      // document never ticks the box that says you accept it.
      _recognizers[document] = TapGestureRecognizer()
        ..onTap = () => _open(document);
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _open(LegalDocumentKind document) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final failed = SnackBar(content: Text(l10n.openLinkFailed));
    final uri = Uri.tryParse(
      legalDocumentUrl(
        document,
        Localizations.localeOf(context).toLanguageTag(),
      ),
    );
    if (uri == null) {
      messenger.showSnackBar(failed);
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) messenger.showSnackBar(failed);
    } catch (e) {
      // No browser, or no platform handler at all: say so instead of throwing
      // out of a tap handler.
      debugPrint('legal: opening $uri failed: $e');
      messenger.showSnackBar(failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final linkStyle = TextStyle(
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.onSurface,
    );

    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final segment in _segments)
            if (segment.document case final document?)
              TextSpan(
                text: document == LegalDocumentKind.terms
                    ? l10n.legalTermsName
                    : l10n.legalPrivacyName,
                style: linkStyle,
                recognizer: _recognizers[document],
              )
            else
              TextSpan(text: segment.text),
        ],
      ),
    );
  }
}
