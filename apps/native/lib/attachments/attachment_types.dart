import 'dart:convert';

import '../voice/agent_generated.dart';

/// An uploaded file the agent can read through `readAttachment`.
class SentAttachment {
  const SentAttachment({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is SentAttachment &&
      other.id == id &&
      other.name == name &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);
}

const _genericMimeTypes = {'', 'application/octet-stream'};

/// HEIC photos are converted to PNG where the platform can decode them.
const convertibleImageMimeTypes = {'image/heic', 'image/heif'};
const _convertibleImageExtensions = {'heic', 'heif'};

String _normalizeMime(String? mimeType) =>
    (mimeType ?? '').split(';').first.trim().toLowerCase();

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}

AttachmentType? attachmentTypeForMime(String? mimeType) {
  final normalized = _normalizeMime(mimeType);
  for (final type in kAttachmentTypes) {
    if (type.mimeType == normalized) return type;
  }
  return null;
}

/// Mirror of `resolveAttachmentType` in packages/shared: the reported type
/// wins, the extension decides only when the platform reports nothing useful.
AttachmentType? resolveAttachmentType(String? mimeType, String fileName) {
  final normalized = _normalizeMime(mimeType);
  if (!_genericMimeTypes.contains(normalized)) {
    final byMime = attachmentTypeForMime(normalized);
    if (byMime != null) return byMime;
  }
  final extension = _extensionOf(fileName);
  for (final type in kAttachmentTypes) {
    if (type.extensions.contains(extension)) return type;
  }
  return null;
}

bool isConvertibleImage(String? mimeType, String fileName) =>
    convertibleImageMimeTypes.contains(_normalizeMime(mimeType)) ||
    _convertibleImageExtensions.contains(_extensionOf(fileName));

final AttachmentType pngAttachmentType = attachmentTypeForMime('image/png')!;

/// The line the model sees for an attachment (live/createToken.ts).
String attachmentLine(SentAttachment attachment) =>
    '[Attachment id=${attachment.id} name=${jsonEncode(attachment.name)} '
    'type=${attachment.kind}]';

/// What a typed turn sends to the model: the text, then one line per file.
String composeMessageText(String text, List<SentAttachment> attachments) => [
  text.trim(),
  ...attachments.map(attachmentLine),
].where((line) => line.isNotEmpty).join('\n');

final _attachmentLinePattern = RegExp(
  r'^\[Attachment id=(\S+) name=("(?:[^"\\]|\\.)*") type=(\w+)\]$',
);

/// The inverse of [composeMessageText], for bubbles rebuilt from the log.
({String text, List<SentAttachment> attachments}) splitAttachmentLines(
  String message,
) {
  final text = <String>[];
  final attachments = <SentAttachment>[];
  for (final line in message.split('\n')) {
    final match = _attachmentLinePattern.firstMatch(line.trim());
    final name = match == null ? null : jsonDecode(match.group(2)!);
    if (match != null && name is String) {
      attachments.add(
        SentAttachment(id: match.group(1)!, name: name, kind: match.group(3)!),
      );
    } else {
      text.add(line);
    }
  }
  return (text: text.join('\n').trim(), attachments: attachments);
}
