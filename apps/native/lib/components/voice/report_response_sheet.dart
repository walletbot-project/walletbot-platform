import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/adaptive_modal.dart';
import 'package:app/voice/agent_report_submitter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Longest note a reporter can add, mirroring `AGENT_REPORT_MAX_NOTE_LENGTH`
/// in `packages/shared/src/agent-reports.ts`. The server enforces it by
/// truncating; this is the field's own cap so the count is visible while typing.
const agentReportMaxNoteLength = 2000;

/// The reason codes the server accepts, in the order the sheet shows them.
/// Mirrors `AGENT_REPORT_REASONS`; a code missing here simply isn't offered.
const agentReportReasons = <String>[
  'offensive',
  'sexual',
  'dangerous',
  'misleading',
  'privacy',
  'other',
];

/// Opens the "report a response" sheet.
///
/// Google Play's AI-Generated Content policy requires an in-app way to flag
/// offensive generated content without leaving the app, and Apple asks for the
/// same through guidelines 1.2 / 4.7.1. [reportedText] is the flagged turn as it
/// was rendered; pass null to report the session instead, which is the path for
/// a reply that was voice-only or has already scrolled away.
///
/// [clientInfo] and [locale] are passed in explicitly because the sheet is
/// pushed on a Navigator above the account-scoped providers — the same reason
/// `showFeedbackSheet` takes them as arguments.
///
/// Resolves true once a report was accepted, so the caller can mark the bubble.
Future<bool> showReportResponseSheet(
  BuildContext context, {
  required ClientInfo clientInfo,
  required String locale,
  String? reportedText,
  String? precedingUserText,
  String? sessionId,
  String? model,
  DateTime? occurredAt,
}) async {
  final reported = await showAdaptiveModal<bool>(
    context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    sheetShape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportResponseSheet(
      submitter: AgentReportSubmitter(
        clientInfo: clientInfo,
        client: context.read<ConvexClient>(),
        resolveLocalAccountId: context
            .read<AuthController>()
            .localAccountIdForSubmission,
      ),
      locale: locale,
      reportedText: reportedText,
      precedingUserText: precedingUserText,
      sessionId: sessionId,
      model: model,
      occurredAt: occurredAt,
    ),
  );
  return reported ?? false;
}

/// The sheet's body: the flagged text, the reason chips, an optional note, the
/// inline error surface and the actions.
///
/// Public so a test can drive it with a stubbed [AgentReportSubmitter]; app code
/// goes through [showReportResponseSheet], which supplies the real one.
class ReportResponseSheet extends StatefulWidget {
  const ReportResponseSheet({
    super.key,
    required this.submitter,
    required this.locale,
    this.reportedText,
    this.precedingUserText,
    this.sessionId,
    this.model,
    this.occurredAt,
  });

  final AgentReportSubmitter submitter;
  final String locale;
  final String? reportedText;
  final String? precedingUserText;
  final String? sessionId;
  final String? model;
  final DateTime? occurredAt;

  @override
  State<ReportResponseSheet> createState() => _ReportResponseSheetState();
}

class _ReportResponseSheetState extends State<ReportResponseSheet> {
  final _noteController = TextEditingController();
  String? _reason;
  var _sending = false;

  /// The last failure, shown inside the sheet.
  ///
  /// Never a snackbar: `ScaffoldMessenger` posts to the [Scaffold] under this
  /// route, which the sheet covers, so a rejection there would be invisible and
  /// a refused send would look like a button that did nothing.
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  AgentReportScope get _scope {
    final text = widget.reportedText?.trim();
    return text == null || text.isEmpty
        ? AgentReportScope.session
        : AgentReportScope.response;
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = l10n.reportResponseReasonRequired);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.submitter.submit(
        reason: reason,
        scope: _scope,
        locale: widget.locale,
        note: _noteController.text.trim(),
        reportedText: widget.reportedText?.trim(),
        precedingUserText: widget.precedingUserText?.trim(),
        sessionId: widget.sessionId,
        model: widget.model,
        occurredAt: widget.occurredAt,
      );
      if (!mounted) return;
      // Popped first, then the snackbar: it belongs to the messenger under this
      // route, so it is only on screen once the sheet is gone.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.reportResponseSent)));
    } on AgentReportException catch (error, stackTrace) {
      // Logged even though the sheet has copy for it: this is a site that flips
      // user-visible state, and `error.cause` is the only record of what the
      // transport or the server actually did.
      debugPrint(
        'agent report: refused as ${error.failure.name}: '
        '${error.cause}\n$stackTrace',
      );
      // The sheet stays open with the reason and the note intact, so a rate
      // limit never costs the user what they wrote.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = switch (error.failure) {
          AgentReportFailure.rateLimited => l10n.reportResponseRateLimited,
          AgentReportFailure.invalid => l10n.reportResponseInvalid,
          AgentReportFailure.offline => l10n.reportResponseOffline,
          AgentReportFailure.failed => l10n.reportResponseFailed,
        };
      });
    } catch (error, stackTrace) {
      debugPrint('agent report: submit failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = l10n.reportResponseFailed;
      });
    }
  }

  String _reasonLabel(AppLocalizations l10n, String reason) => switch (reason) {
    'offensive' => l10n.reportReasonOffensive,
    'sexual' => l10n.reportReasonSexual,
    'dangerous' => l10n.reportReasonDangerous,
    'misleading' => l10n.reportReasonMisleading,
    'privacy' => l10n.reportReasonPrivacy,
    _ => l10n.reportReasonOther,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final error = _error;
    final reportedText = widget.reportedText?.trim();
    final isSession = _scope == AgentReportScope.session;

    // `viewInsets.bottom` keeps the sheet above the keyboard; `SafeArea`
    // (bottom only) keeps the actions clear of the system navigation bar.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.reportResponseTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSession
                    ? l10n.reportResponseSessionSubtitle
                    : l10n.reportResponseSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Shown before sending, because the report stores a copy of it
              // server-side. A sheet that sent the text silently would hide
              // that from the person filing the report.
              if (reportedText != null && reportedText.isNotEmpty) ...[
                Text(
                  l10n.reportResponseReportedTextLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      reportedText,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ] else
                Text(
                  l10n.reportResponseSessionNotice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 16),

              Text(
                l10n.reportResponseReasonLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in agentReportReasons)
                    ChoiceChip(
                      label: Text(_reasonLabel(l10n, reason)),
                      selected: _reason == reason,
                      onSelected: _sending
                          ? null
                          : (_) => setState(() {
                              _reason = reason;
                              _error = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _noteController,
                enabled: !_sending,
                minLines: 3,
                maxLines: 6,
                maxLength: agentReportMaxNoteLength,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: l10n.reportResponseNoteLabel,
                  hintText: l10n.reportResponseNoteHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),

              Text(
                l10n.reportResponsePrivacyNotice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              if (error != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(
                  message: error,
                  onDismiss: () => setState(() => _error = null),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sending || _reason == null ? null : _send,
                      child: Text(
                        _sending
                            ? l10n.reportResponseSending
                            : l10n.reportResponseSend,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet's own error surface. Inside the sheet because a snackbar posts to
/// the [Scaffold] this route covers, where the user never sees it.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.feedbackErrorDismiss,
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
