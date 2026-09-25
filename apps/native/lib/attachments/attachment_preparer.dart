import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../voice/agent_generated.dart';
import 'attachment_types.dart';

/// A file picked, dropped or pasted, before it is checked and uploaded.
/// [size] is known up front for picked files, so an oversized one is refused
/// before its bytes are read.
class PickedAttachment {
  const PickedAttachment({
    required this.name,
    required this.readBytes,
    this.mimeType,
    this.size,
  });

  final String name;
  final String? mimeType;
  final int? size;
  final Future<Uint8List> Function() readBytes;
}

class PreparedAttachment {
  const PreparedAttachment({
    required this.name,
    required this.bytes,
    required this.type,
  });

  final String name;
  final Uint8List bytes;
  final AttachmentType type;
}

enum PrepareFailure { unsupportedType, tooLarge }

sealed class PrepareOutcome {
  const PrepareOutcome();
}

class Prepared extends PrepareOutcome {
  const Prepared(this.file);
  final PreparedAttachment file;
}

class PrepareFailed extends PrepareOutcome {
  const PrepareFailed(this.failure);
  final PrepareFailure failure;
}

/// Returns PNG bytes no larger than [kAttachmentImageMaxDimension] on the long
/// edge, the input itself when it already fits and [force] is false, or null
/// when the platform cannot decode it.
typedef ImageResizer =
    Future<Uint8List?> Function(Uint8List bytes, {required bool force});

Future<Uint8List?> resizeToPng(Uint8List bytes, {required bool force}) async {
  final ui.ImmutableBuffer buffer;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  } catch (_) {
    return null;
  }
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longEdge = math.max(descriptor.width, descriptor.height);
    if (!force && longEdge <= kAttachmentImageMaxDimension) return bytes;
    final scale = math.min(1.0, kAttachmentImageMaxDimension / longEdge);
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

String _withExtension(String name, String extension) {
  final dot = name.lastIndexOf('.');
  return '${dot > 0 ? name.substring(0, dot) : name}.$extension';
}

/// Resolves what the file is and makes it uploadable: HEIC becomes PNG,
/// oversized images are downscaled, and the limit of its kind is checked on
/// what will actually be sent. Mirrors `prepareFile` on web.
Future<PrepareOutcome> prepareAttachment(
  PickedAttachment picked, {
  ImageResizer resize = resizeToPng,
}) async {
  final convertible = isConvertibleImage(picked.mimeType, picked.name);
  final type = convertible
      ? pngAttachmentType
      : resolveAttachmentType(picked.mimeType, picked.name);
  if (type == null) return const PrepareFailed(PrepareFailure.unsupportedType);
  final size = picked.size;
  if (size != null && size > type.maxBytes) {
    return const PrepareFailed(PrepareFailure.tooLarge);
  }
  final bytes = await picked.readBytes();
  if (bytes.length > type.maxBytes) {
    return const PrepareFailed(PrepareFailure.tooLarge);
  }
  if (type.kind != 'image') {
    return Prepared(
      PreparedAttachment(name: picked.name, bytes: bytes, type: type),
    );
  }

  final resized = await resize(bytes, force: convertible);
  if (resized == null) {
    // An accepted image the platform cannot decode is still sent as-is; only
    // HEIC depends on the conversion.
    return convertible
        ? const PrepareFailed(PrepareFailure.unsupportedType)
        : Prepared(
            PreparedAttachment(name: picked.name, bytes: bytes, type: type),
          );
  }
  if (identical(resized, bytes)) {
    return Prepared(
      PreparedAttachment(name: picked.name, bytes: bytes, type: type),
    );
  }
  if (resized.length > pngAttachmentType.maxBytes) {
    return const PrepareFailed(PrepareFailure.tooLarge);
  }
  return Prepared(
    PreparedAttachment(
      name: _withExtension(picked.name, 'png'),
      bytes: resized,
      type: pngAttachmentType,
    ),
  );
}
