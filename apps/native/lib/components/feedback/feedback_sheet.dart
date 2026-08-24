import 'dart:io';

import 'package:app/app_config/client_info.dart';
import 'package:app/feedback/feedback_limits.dart';
import 'package:app/feedback/feedback_submitter.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/adaptive_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Opens the "send feedback" sheet: a message plus up to
/// [feedbackMaxAttachments] files of [feedbackMaxAttachmentBytes] each.
///
/// [clientInfo] and [locale] are passed in explicitly because the sheet is
/// pushed on a Navigator above the account-scoped providers — the same reason
/// `showAddWidgetSheet` takes its repositories as an argument.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required ClientInfo clientInfo,
  required String locale,
}) => showAdaptiveModal<void>(
  context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  sheetShape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => _FeedbackSheet(
    submitter: FeedbackSubmitter(clientInfo: clientInfo),
    locale: locale,
  ),
);

/// Prefers the stream `file_picker` already opened; falls back to the cached
/// copy on disk, so a 100 MB attachment is never buffered whole in memory.
Future<List<FeedbackAttachment>> _pickFiles() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    withReadStream: true,
  );
  final files = result?.files ?? const <PlatformFile>[];
  final attachments = <FeedbackAttachment>[];
  for (final file in files) {
    final readStream = file.readStream;
    final path = file.path;
    if (readStream == null && path == null) continue;
    attachments.add(
      FeedbackAttachment(
        name: file.name,
        size: file.size,
        openRead: readStream != null
            ? () => readStream
            : () => File(path!).openRead(),
      ),
    );
  }
  return attachments;
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.submitter, required this.locale});

  final FeedbackSubmitter submitter;
  final String locale;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _messageController = TextEditingController();
  final _attachments = <FeedbackAttachment>[];
  var _sending = false;

  /// `(uploaded, total)` while attachments are going up, so a ten-file
  /// submission doesn't look stuck behind one spinner.
  (int, int)? _uploadProgress;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pick() async {
    final l10n = context.l10n;
    final List<FeedbackAttachment> picked;
    try {
      picked = await _pickFiles();
    } catch (error, stackTrace) {
      debugPrint('feedback: picking files failed: $error\n$stackTrace');
      _showMessage(l10n.feedbackSendFailed);
      return;
    }
    if (!mounted || picked.isEmpty) return;

    final accepted = <FeedbackAttachment>[];
    for (final attachment in picked) {
      if (attachment.size > feedbackMaxAttachmentBytes) {
        _showMessage(
          l10n.feedbackFileTooLarge(
            attachment.name,
            formatFileSize(feedbackMaxAttachmentBytes),
          ),
        );
        continue;
      }
      if (_attachments.length + accepted.length >= feedbackMaxAttachments) {
        _showMessage(l10n.feedbackTooManyFiles(feedbackMaxAttachments));
        break;
      }
      accepted.add(attachment);
    }
    if (accepted.isEmpty) return;
    setState(() => _attachments.addAll(accepted));
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      _showMessage(l10n.feedbackMessageRequired);
      return;
    }

    setState(() {
      _sending = true;
      _uploadProgress = null;
    });
    // The in-progress state lives on the send button (`_sendLabel`), not in a
    // snackbar: a queued snackbar would hold the outcome message back for
    // seconds after the submission actually finished.
    try {
      await widget.submitter.submit(
        message: message,
        attachments: List.of(_attachments),
        locale: widget.locale,
        onUploadProgress: (uploaded, total) {
          if (!mounted || total == 0) return;
          setState(() => _uploadProgress = (uploaded, total));
        },
      );
      if (!mounted) return;
      _showMessage(l10n.feedbackSent);
      Navigator.of(context).pop();
    } on FeedbackException catch (error) {
      // The sheet stays open with the text and the picked files intact, so a
      // rate limit or a dropped upload never costs the user what they wrote.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _uploadProgress = null;
      });
      _showMessage(switch (error.failure) {
        FeedbackFailure.rateLimited => l10n.feedbackRateLimited,
        FeedbackFailure.attachmentRejected => l10n.feedbackAttachmentRejected,
        FeedbackFailure.messageInvalid => l10n.feedbackMessageRequired,
        FeedbackFailure.failed => l10n.feedbackSendFailed,
      });
    } catch (error, stackTrace) {
      debugPrint('feedback: submit failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _uploadProgress = null;
      });
      _showMessage(l10n.feedbackSendFailed);
    }
  }

  /// While uploading, the button reports which attachment is in flight; a
  /// ten-file submission would otherwise sit on one unchanging label for
  /// minutes.
  String _sendLabel(AppLocalizations l10n) {
    if (!_sending) return l10n.feedbackSend;
    final progress = _uploadProgress;
    if (progress == null || progress.$1 >= progress.$2) {
      return l10n.feedbackSending;
    }
    return l10n.feedbackUploading(progress.$1 + 1, progress.$2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                l10n.feedbackTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.feedbackSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _messageController,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                maxLength: feedbackMaxMessageLength,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: l10n.feedbackMessageLabel,
                  hintText: l10n.feedbackMessageHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),

              OutlinedButton.icon(
                onPressed:
                    _sending || _attachments.length >= feedbackMaxAttachments
                    ? null
                    : _pick,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(l10n.feedbackAttach),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.feedbackAttachmentsCount(
                  _attachments.length,
                  feedbackMaxAttachments,
                  formatFileSize(feedbackMaxAttachmentBytes),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final (index, attachment) in _attachments.indexed)
                  _AttachmentTile(
                    name: attachment.name,
                    size: formatFileSize(attachment.size),
                    onRemove: _sending
                        ? null
                        : () => setState(() => _attachments.removeAt(index)),
                  ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      child: Text(_sendLabel(l10n)),
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

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.name,
    required this.size,
    required this.onRemove,
  });

  final String name;
  final String size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  size,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.feedbackRemoveAttachment,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// A file size for display. Unit symbols only — no localized copy involved, the
/// same way the app shows currency codes.
String formatFileSize(int bytes) {
  const megabyte = 1024 * 1024;
  if (bytes >= megabyte) {
    final megabytes = bytes / megabyte;
    final rounded = megabytes >= 10
        ? megabytes.round().toString()
        : megabytes.toStringAsFixed(1);
    return '$rounded MB';
  }
  return '${(bytes / 1024).clamp(1, double.infinity).round()} KB';
}
