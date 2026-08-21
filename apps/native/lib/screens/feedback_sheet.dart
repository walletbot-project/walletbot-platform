import 'package:app/app_config/client_info.dart';
import 'package:app/feedback/feedback_service.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/shared/adaptive_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Opens the feedback form as an adaptive modal — a bottom sheet on phones, a
/// dialog on large windows — matching every other transient surface in the app.
///
/// [clientInfo] is passed in explicitly because the sheet is pushed on a
/// Navigator that sits above the app-level providers (same reason
/// `showAddWidgetSheet` takes `repos`).
Future<void> showFeedbackSheet(
  BuildContext context, {
  required ClientInfo clientInfo,
}) => showAdaptiveModal<void>(
  context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _FeedbackSheet(clientInfo: clientInfo),
);

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.clientInfo});

  final ClientInfo clientInfo;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();
  final _files = <PlatformFile>[];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final l10n = context.l10n;
    final remaining = feedbackMaxFiles - _files.length;
    if (remaining <= 0) {
      _showMessage(l10n.feedbackTooManyFiles(feedbackMaxFiles));
      return;
    }

    final FilePickerResult? result;
    try {
      // `FileType.any`: a screenshot, a screen recording and an exported log
      // are all legitimate evidence for a bug report.
      result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
    } catch (e) {
      debugPrint('feedback: file picker failed: $e');
      if (mounted) _showMessage(l10n.feedbackSendFailed);
      return;
    }
    if (result == null || !mounted) return;

    final picked = result.files;
    final tooBig = picked.where((file) => file.size > feedbackMaxFileBytes);
    if (tooBig.isNotEmpty) {
      _showMessage(
        l10n.feedbackFileTooLarge(tooBig.first.name, feedbackMaxFileMb),
      );
      return;
    }
    if (picked.length > remaining) {
      _showMessage(l10n.feedbackTooManyFiles(feedbackMaxFiles));
      return;
    }

    setState(() => _files.addAll(picked));
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    // Captured before the pop below: after it, this subtree is on its way out
    // and looking the messenger up through its context would be too late.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = _controller.text.trim();
    if (text.isEmpty && _files.isEmpty) {
      _showMessage(l10n.feedbackEmpty);
      return;
    }
    if (text.length > feedbackMaxTextChars) {
      _showMessage(l10n.feedbackTextTooLong(feedbackMaxTextChars));
      return;
    }

    setState(() => _sending = true);
    final service = FeedbackService(clientInfo: widget.clientInfo);
    final result = await service.submit(
      text: text,
      files: List.of(_files),
      locale: Localizations.localeOf(context).toLanguageTag(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.ok) {
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(content: Text(l10n.feedbackSent)));
      return;
    }
    // A failure keeps the sheet open so the typed report and its attachments
    // survive for a retry — never discarded on an error.
    messenger?.showSnackBar(SnackBar(content: Text(_messageFor(result, l10n))));
  }

  String _messageFor(
    FeedbackResult result,
    AppLocalizations l10n,
  ) => switch (result.error) {
    FeedbackError.rateLimited => l10n.feedbackRateLimited,
    FeedbackError.empty => l10n.feedbackEmpty,
    FeedbackError.textTooLong => l10n.feedbackTextTooLong(feedbackMaxTextChars),
    FeedbackError.tooManyFiles => l10n.feedbackTooManyFiles(feedbackMaxFiles),
    // The server checks stored sizes, so it cannot name the file; only the
    // picker-time check above can.
    FeedbackError.fileTooLarge => l10n.feedbackFileTooLargeGeneric(
      feedbackMaxFileMb,
    ),
    FeedbackError.unknownAttachment => l10n.feedbackUnknownAttachment,
    FeedbackError.uploadFailed => l10n.feedbackUploadFailed(
      result.failedFileName ?? '',
    ),
    FeedbackError.network || null => l10n.feedbackSendFailed,
  };

  /// For messages posted while the sheet stays open. The success path captures
  /// the messenger before popping instead — see [_send].
  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      minimum: const EdgeInsets.only(bottom: 16),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l10n.sendFeedback,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.feedbackIntro,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        enabled: !_sending,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: feedbackMaxTextChars,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: l10n.feedbackMessageLabel,
                          hintText: l10n.feedbackMessageHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.feedbackAttachments,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _sending || _files.length >= feedbackMaxFiles
                                ? null
                                : _pickFiles,
                            icon: const Icon(
                              Icons.attach_file_rounded,
                              size: 18,
                            ),
                            label: Text(l10n.feedbackAddFiles),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.feedbackAttachmentsHint(
                          feedbackMaxFiles,
                          feedbackMaxFileMb,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (var index = 0; index < _files.length; index++)
                        _AttachmentRow(
                          file: _files[index],
                          onRemove: _sending
                              ? null
                              : () => setState(() => _files.removeAt(index)),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.feedbackSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.file, required this.onRemove});

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Icon(_iconFor(file.name), size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatBytes(file.size),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: context.l10n.feedbackRemoveFile(file.name),
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the file's kind, derived from the same extension the upload's
/// Content-Type comes from (`contentTypeFor`).
IconData _iconFor(String filename) {
  final type = contentTypeFor(filename);
  if (type.startsWith('image/')) return Icons.image_rounded;
  if (type.startsWith('video/')) return Icons.movie_rounded;
  if (type.startsWith('audio/')) return Icons.graphic_eq_rounded;
  return Icons.description_rounded;
}

String _formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  final kb = (bytes / 1024).ceil();
  return '$kb KB';
}
