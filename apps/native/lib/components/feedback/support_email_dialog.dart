import 'package:app/app_config/client_info.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the "write to support" dialog: the mailbox, a button that hands the
/// message to the device's mail app, and a copy button for when there isn't one.
///
/// [draft] is whatever the user already typed in the feedback sheet. It is
/// carried into the mail body so switching to email never costs them the text.
Future<void> showSupportEmailDialog(
  BuildContext context, {
  required ClientInfo clientInfo,
  required String draft,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SupportEmailDialog(clientInfo: clientInfo, draft: draft),
);

/// The `mailto:` URI for one support message.
///
/// Built by hand rather than with [Uri]'s `queryParameters`, which encodes
/// spaces as `+`: correct for form bodies, wrong in a mail subject, where
/// several clients show the plus signs verbatim.
@visibleForTesting
Uri supportMailtoUri({
  required String address,
  required String subject,
  required String body,
}) => Uri.parse(
  'mailto:$address'
  '?subject=${Uri.encodeComponent(subject)}'
  '&body=${Uri.encodeComponent(body)}',
);

class _SupportEmailDialog extends StatefulWidget {
  const _SupportEmailDialog({required this.clientInfo, required this.draft});

  final ClientInfo clientInfo;
  final String draft;

  @override
  State<_SupportEmailDialog> createState() => _SupportEmailDialogState();
}

class _SupportEmailDialogState extends State<_SupportEmailDialog> {
  /// Confirmations and failures are shown inside the dialog on purpose: a
  /// snackbar posts to the [Scaffold] underneath, where this route covers it.
  var _copied = false;
  var _launchFailed = false;

  Future<void> _copy(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() {
      _copied = true;
      _launchFailed = false;
    });
  }

  Future<void> _openMailApp(AppLocalizations l10n, String address) async {
    final body = widget.draft.isEmpty
        ? l10n.feedbackEmailBodyFooter(_client)
        : '${widget.draft}\n\n${l10n.feedbackEmailBodyFooter(_client)}';
    final uri = supportMailtoUri(
      address: address,
      subject: l10n.feedbackEmailSubject,
      body: body,
    );

    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // No mail app, or no platform handler at all. Say so instead of throwing
      // out of a tap handler.
      debugPrint('feedback: opening $address failed: $error');
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _launchFailed = true;
      _copied = false;
    });
  }

  String get _client =>
      '${widget.clientInfo.platform} ${widget.clientInfo.appVersion}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final address = l10n.feedbackSupportEmail;

    return AlertDialog(
      icon: const Icon(Icons.mail_outline_rounded),
      title: Text(l10n.feedbackEmailTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.feedbackEmailBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _copy(address),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        address,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l10n.feedbackEmailCopy,
                      onPressed: () => _copy(address),
                      icon: Icon(
                        _copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_copied || _launchFailed) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _copied ? Icons.check_circle_outline : Icons.info_outline,
                  size: 18,
                  color: _copied
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _copied
                        ? l10n.feedbackEmailCopied
                        : l10n.feedbackEmailNoApp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _copied
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton.icon(
          onPressed: () => _openMailApp(l10n, address),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(l10n.feedbackEmailOpen),
        ),
      ],
    );
  }
}
