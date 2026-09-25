import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../voice/agent_generated.dart';
import 'attachment_preparer.dart';
import 'attachment_types.dart';

/// Formats a dropped or pasted item can arrive in, most specific first, with
/// the MIME type its upload uses. OFX/QIF have no clipboard format; they come
/// in through the file picker.
final List<({FileFormat format, String mimeType, String extension})>
_fileFormats = [
  (format: Formats.pdf, mimeType: 'application/pdf', extension: 'pdf'),
  (
    format: Formats.docx,
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    extension: 'docx',
  ),
  (
    format: Formats.xlsx,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    extension: 'xlsx',
  ),
  (format: Formats.csv, mimeType: 'text/csv', extension: 'csv'),
  (format: Formats.json, mimeType: 'application/json', extension: 'json'),
  (format: Formats.md, mimeType: 'text/markdown', extension: 'md'),
  (format: Formats.heic, mimeType: 'image/heic', extension: 'heic'),
  (format: Formats.heif, mimeType: 'image/heif', extension: 'heif'),
  (format: Formats.jpeg, mimeType: 'image/jpeg', extension: 'jpg'),
  (format: Formats.png, mimeType: 'image/png', extension: 'png'),
  (format: Formats.webp, mimeType: 'image/webp', extension: 'webp'),
  (format: Formats.gif, mimeType: 'image/gif', extension: 'gif'),
  (format: Formats.plainTextFile, mimeType: 'text/plain', extension: 'txt'),
];

/// What the chat's drop region accepts.
final List<DataFormat> attachmentDataFormats = [
  for (final entry in _fileFormats) entry.format,
];

/// Requests the first attachment format [reader] offers. Inside a drop this
/// must be called before `onPerformDrop` returns: mobile platforms only hand
/// out the data while the drop is being performed.
Future<PickedAttachment?> requestAttachment(
  DataReader reader, {
  required String fallbackName,
}) {
  for (final entry in _fileFormats) {
    if (!reader.canProvide(entry.format)) continue;
    final completer = Completer<PickedAttachment?>();
    final progress = reader.getFile(
      entry.format,
      (file) async {
        try {
          final bytes = await file.readAll();
          completer.complete(
            PickedAttachment(
              name: file.fileName ?? '$fallbackName.${entry.extension}',
              mimeType: entry.mimeType,
              size: bytes.length,
              readBytes: () async => bytes,
            ),
          );
        } catch (error) {
          debugPrint('[attachments] reading a dropped file failed: $error');
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (error) {
        debugPrint('[attachments] dropped file unavailable: $error');
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) continue;
    return completer.future;
  }
  return Future.value(null);
}

/// Every attachment on the system clipboard; empty when there is none or the
/// platform has no clipboard API.
Future<List<PickedAttachment>> readClipboardAttachments({
  required String fallbackName,
}) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return const [];
  final reader = await clipboard.read();
  final picked = await Future.wait([
    for (final (index, item) in reader.items.indexed)
      requestAttachment(item, fallbackName: '$fallbackName ${index + 1}'),
  ]);
  return picked.nonNulls.toList();
}

/// An image a keyboard inserted into the composer (Android's Gboard offers
/// copied images this way).
PickedAttachment? insertedContentAttachment(
  KeyboardInsertedContent content, {
  required String fallbackName,
}) {
  final data = content.data;
  if (data == null) return null;
  final extension = content.mimeType.split('/').last;
  return PickedAttachment(
    name: '$fallbackName.$extension',
    mimeType: content.mimeType,
    size: data.length,
    readBytes: () async => data,
  );
}

/// MIME types the composer accepts from a keyboard.
const insertableImageMimeTypes = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
];

PickedAttachment _fromXFile(XFile file, int size) => PickedAttachment(
  name: file.name,
  mimeType: file.mimeType,
  size: size,
  readBytes: file.readAsBytes,
);

final _imagePicker = ImagePicker();

/// iOS and Android only: desktop needs a camera delegate the app does not
/// provide, so the screen hides the option there.
Future<PickedAttachment?> takePhotoAttachment() async {
  final photo = await _imagePicker.pickImage(
    source: ImageSource.camera,
    maxWidth: kAttachmentImageMaxDimension.toDouble(),
    maxHeight: kAttachmentImageMaxDimension.toDouble(),
    imageQuality: 85,
  );
  if (photo == null) return null;
  return _fromXFile(photo, await photo.length());
}

Future<List<PickedAttachment>> pickPhotoAttachments({
  required int limit,
}) async {
  if (limit <= 0) return const [];
  final photos = limit == 1
      ? [
          ?await _imagePicker.pickImage(
            source: ImageSource.gallery,
            maxWidth: kAttachmentImageMaxDimension.toDouble(),
            maxHeight: kAttachmentImageMaxDimension.toDouble(),
            imageQuality: 85,
          ),
        ]
      : await _imagePicker.pickMultiImage(
          maxWidth: kAttachmentImageMaxDimension.toDouble(),
          maxHeight: kAttachmentImageMaxDimension.toDouble(),
          imageQuality: 85,
          limit: limit,
        );
  return [for (final photo in photos) _fromXFile(photo, await photo.length())];
}

/// Every accepted extension, plus HEIC which is converted before upload.
final List<String> _pickableExtensions = [
  for (final type in kAttachmentTypes) ...type.extensions,
  'heic',
  'heif',
];

Future<List<PickedAttachment>> pickFileAttachments() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: _pickableExtensions,
  );
  final files = result?.files ?? const <PlatformFile>[];
  return [
    for (final file in files)
      if (file.path case final path?)
        PickedAttachment(
          name: file.name,
          mimeType: resolveAttachmentType(null, file.name)?.mimeType,
          size: file.size,
          readBytes: () => File(path).readAsBytes(),
        ),
  ];
}
