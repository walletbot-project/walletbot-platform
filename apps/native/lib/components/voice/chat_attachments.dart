import 'dart:io';

import 'package:app/attachments/attachment_types.dart';
import 'package:app/attachments/chat_attachments_controller.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

IconData attachmentKindIcon(String? kind) => switch (kind) {
  'image' => Icons.image_rounded,
  'pdf' => Icons.picture_as_pdf_rounded,
  'document' => Icons.description_rounded,
  'spreadsheet' => Icons.table_chart_rounded,
  'text' => Icons.article_rounded,
  _ => Icons.insert_drive_file_rounded,
};

/// The camera needs a delegate on desktop that the app does not provide.
bool get canTakePhoto => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

enum AttachSource { camera, photos, files }

/// The composer's attach button: a menu of where the file comes from.
class AttachButton extends StatelessWidget {
  const AttachButton({
    super.key,
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<AttachSource> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<AttachSource>(
      enabled: enabled,
      tooltip: l10n.attachFile,
      icon: const Icon(Icons.attach_file_rounded),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (canTakePhoto)
          PopupMenuItem(
            value: AttachSource.camera,
            child: ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(l10n.attachTakePhoto),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: AttachSource.photos,
          child: ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: Text(l10n.attachPhotoLibrary),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: AttachSource.files,
          child: ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(l10n.attachChooseFile),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Files waiting in the composer, with their upload state.
class PendingAttachmentChips extends StatelessWidget {
  const PendingAttachmentChips({
    super.key,
    required this.items,
    required this.onRemove,
  });

  final List<PendingAttachment> items;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: item.status == PendingAttachmentStatus.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.preview case final preview?)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      preview,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      cacheWidth: 96,
                      errorBuilder: (_, _, _) => Icon(
                        attachmentKindIcon(item.kind),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Icon(
                    attachmentKindIcon(item.kind),
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (item.status == PendingAttachmentStatus.uploading) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: l10n.attachmentUploading,
                    ),
                  ),
                ],
                if (item.status == PendingAttachmentStatus.failed) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.error_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                    semanticLabel: l10n.attachmentUploadFailed,
                  ),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: l10n.attachmentRemove,
                  onPressed: () => onRemove(item.localId),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The files a sent message carried, inside its bubble.
class SentAttachmentChips extends StatelessWidget {
  const SentAttachmentChips({super.key, required this.attachments});

  final List<SentAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  attachmentKindIcon(attachment.kind),
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shown over the chat while files are dragged over it.
class AttachmentDropOverlay extends StatelessWidget {
  const AttachmentDropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file_rounded,
                size: 40,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.attachmentDropHere,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
