import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../voice/agent_generated.dart';
import 'attachment_preparer.dart';
import 'attachment_types.dart';
import 'attachment_uploader.dart';

enum PendingAttachmentStatus { uploading, ready, failed }

class PendingAttachment {
  PendingAttachment({required this.localId, required this.name, this.kind});

  final String localId;
  String name;
  String? kind;

  /// The prepared image bytes, for the chip's thumbnail.
  Uint8List? preview;
  PendingAttachmentStatus status = PendingAttachmentStatus.uploading;
  SentAttachment? attachment;
}

/// Files waiting in the chat composer. Each one uploads as soon as it is
/// added, one at a time like feedback (every POST has a two-minute server
/// deadline), so pressing send only carries the attachment ids.
class ChatAttachmentsController extends ChangeNotifier {
  ChatAttachmentsController({
    required this.uploader,
    required this.onFailure,
    this.prepare = prepareAttachment,
  });

  final AttachmentUploader uploader;

  /// Called once per failed file that is still in the composer.
  final void Function(AttachmentFailure failure, String name) onFailure;
  final Future<PrepareOutcome> Function(PickedAttachment) prepare;

  final List<PendingAttachment> _items = [];
  Future<void> _queue = Future.value();
  int _counter = 0;
  bool _disposed = false;

  List<PendingAttachment> get items => List.unmodifiable(_items);
  bool get isUploading =>
      _items.any((item) => item.status == PendingAttachmentStatus.uploading);
  bool get isFull => _items.length >= kAttachmentMaxPerMessage;

  /// Adds what fits under [kAttachmentMaxPerMessage] and returns how many
  /// were accepted; the caller tells the user about the rest.
  int add(List<PickedAttachment> files) {
    final room = math.max(0, kAttachmentMaxPerMessage - _items.length);
    final accepted = files.take(room).toList(growable: false);
    if (accepted.isEmpty) return 0;
    final batch = [
      for (final file in accepted)
        (
          file: file,
          item: PendingAttachment(
            localId: 'a${++_counter}',
            name: file.name,
            kind: isConvertibleImage(file.mimeType, file.name)
                ? 'image'
                : resolveAttachmentType(file.mimeType, file.name)?.kind,
          ),
        ),
    ];
    _items.addAll(batch.map((entry) => entry.item));
    _notify();
    _queue = _queue.then((_) async {
      for (final entry in batch) {
        await _process(entry.file, entry.item);
      }
    });
    return accepted.length;
  }

  Future<void> _process(PickedAttachment file, PendingAttachment item) async {
    try {
      final outcome = await prepare(file);
      switch (outcome) {
        case PrepareFailed(:final failure):
          _fail(
            item,
            failure == PrepareFailure.tooLarge
                ? AttachmentFailure.tooLarge
                : AttachmentFailure.unsupportedType,
          );
        case Prepared(file: final prepared):
          if (prepared.type.kind == 'image') item.preview = prepared.bytes;
          _notify();
          final sent = await uploader.upload(prepared);
          item
            ..status = PendingAttachmentStatus.ready
            ..attachment = sent
            ..name = sent.name
            ..kind = sent.kind;
          _notify();
      }
    } on AttachmentUploadException catch (error) {
      debugPrint('[attachments] upload failed: $error');
      _fail(item, error.failure);
    } catch (error) {
      debugPrint('[attachments] attaching failed: $error');
      _fail(item, AttachmentFailure.failed);
    }
  }

  void _fail(PendingAttachment item, AttachmentFailure failure) {
    item.status = PendingAttachmentStatus.failed;
    _notify();
    if (!_disposed && _items.contains(item)) onFailure(failure, item.name);
  }

  void remove(String localId) {
    _items.removeWhere((item) => item.localId == localId);
    _notify();
  }

  /// Hands the uploaded attachments to the message being sent and empties the
  /// composer. Failed ones are dropped with them; they already said so.
  List<SentAttachment> take() {
    final sent = [
      for (final item in _items)
        if (item.status == PendingAttachmentStatus.ready &&
            item.attachment != null)
          item.attachment!,
    ];
    _items.clear();
    _notify();
    return sent;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
