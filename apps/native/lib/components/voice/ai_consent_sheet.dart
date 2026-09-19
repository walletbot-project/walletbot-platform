import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/database.dart' show LegalDocumentKind;
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:app/shared/adaptive_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// How [ensureAiConsent] ended, so each caller can report it in its own idiom
/// (a system line in the agent chat, a snackbar on the WhatsApp screen).
enum AiConsentOutcome {
  /// Already consented, not applicable, or the user just agreed.
  granted,

  /// The user said no, or dismissed the sheet.
  declined,

  /// The user agreed but the consent could not be recorded.
  failed,
}

/// The consent gate every entry point to the agent runs before data can reach
/// the AI providers: the voice/text session and the WhatsApp link flow.
///
/// [consent] null (widget tests, and everything that is not iOS) or a disabled
/// `aiConsent` flag means no gate. `orElse: true` on the flag because this is a
/// control the app is required to show, so a config call that never landed must
/// not be able to take it away.
Future<AiConsentOutcome> ensureAiConsent(
  BuildContext context,
  AiConsentController? consent,
) async {
  if (consent == null) {
    // A missing controller means "no gate", which is right for widget tests
    // and every non-iOS build — and wrong, silently, if the route simply
    // failed to carry it down (the voice route is pushed on the root
    // navigator, above the account-scoped providers). Assert rather than let
    // that pass unnoticed in development.
    assert(
      clientPlatform() != 'ios',
      'ai_consent: no AiConsentController above this context on iOS. The gate '
      'would pass silently — provide it over the route, as _openVoice does.',
    );
    return AiConsentOutcome.granted;
  }
  if (!consent.isApplicable) return AiConsentOutcome.granted;
  final gated =
      context.read<AppConfigController?>()?.isFlagEnabled(
        'aiConsent',
        orElse: true,
      ) ??
      true;
  if (!gated) return AiConsentOutcome.granted;

  if (!consent.resolved) await consent.load();
  if (consent.accepted) return AiConsentOutcome.granted;
  if (!context.mounted) return AiConsentOutcome.declined;

  if (!await showAiConsentSheet(context)) return AiConsentOutcome.declined;

  try {
    await consent.accept();
  } catch (error) {
    // A remote account records the consent server-side first, so a failed
    // write means there is nothing for the server-side checks to find.
    debugPrint('ai_consent: recording consent failed: $error');
    return AiConsentOutcome.failed;
  }
  return AiConsentOutcome.granted;
}

/// Opens the AI disclosure and asks for permission.
///
/// Resolves true only when the user actively agreed. Dismissing it — the
/// button, the scrim or the back gesture — is a refusal, so the caller must
/// not start a session on anything but true.
///
/// Apple guideline 5.1.2(i): the disclosure names the providers and the data
/// sent to them before anything leaves the device, which the Privacy Policy
/// alone does not satisfy.
Future<bool> showAiConsentSheet(BuildContext context) async {
  final agreed = await showAdaptiveModal<bool>(
    context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    sheetShape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const AiConsentSheet(),
  );
  return agreed ?? false;
}

/// The sheet's body. Public so a widget test can pump it directly.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  Future<void> _openPolicy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = SnackBar(content: Text(context.l10n.openLinkFailed));
    final uri = Uri.tryParse(
      legalDocumentUrl(
        LegalDocumentKind.privacy,
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
      debugPrint('ai_consent: opening $uri failed: $e');
      messenger.showSnackBar(failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final items = <String>[
      l10n.aiConsentItemAudio,
      l10n.aiConsentItemProfile,
      l10n.aiConsentItemFinancial,
      l10n.aiConsentItemMemories,
      l10n.aiConsentItemActions,
    ];

    // The actions stay pinned below the scroll area: a consent gate whose
    // accept button is under the fold reads as a dead end, and the disclosure
    // is long enough to overflow a short window.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.aiConsentTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.aiConsentIntro,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.aiConsentWhatWeSend,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in items) _Bullet(text: item),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => _openPolicy(context),
                        child: Text(l10n.aiConsentReadPolicy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.aiConsentAccept),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.aiConsentDecline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Text('•', style: style),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
