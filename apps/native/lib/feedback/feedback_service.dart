import 'dart:io';

import 'package:app/app_config/client_info.dart';
import 'package:app/sync/wire.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Mirror of the caps in `packages/shared/src/feedback.ts`. The backend
/// re-checks every one of them against what was actually stored, so these are
/// here to tell the user *before* they spend an upload — not to be trusted.
/// Change both together.
const feedbackMaxFiles = 5;
const feedbackMaxFileBytes = 25 * 1024 * 1024;
const feedbackMaxTextChars = 4000;
const feedbackMaxFileMb = feedbackMaxFileBytes ~/ (1024 * 1024);

/// Why a submission did not go through, in the vocabulary the sheet renders.
///
/// Mirrors `FeedbackRejection` in
/// `packages/backend/convex/feedback/helpers.ts` plus the two failures that can
/// only happen client-side ([uploadFailed], [network]).
enum FeedbackError {
  rateLimited,
  empty,
  textTooLong,
  tooManyFiles,
  fileTooLarge,
  unknownAttachment,

  /// A byte upload was rejected or never completed.
  uploadFailed,

  /// Anything else: no connectivity, a wedged socket, an unexpected shape.
  network,
}

/// Maps the backend's `error` string onto [FeedbackError]. An unrecognized
/// value degrades to [FeedbackError.network] rather than being reported as
/// success — a client that does not understand a refusal must still refuse.
FeedbackError _errorFromWire(Object? raw) => switch (raw) {
  'rate_limited' => FeedbackError.rateLimited,
  'empty' => FeedbackError.empty,
  'text_too_long' => FeedbackError.textTooLong,
  'too_many_files' => FeedbackError.tooManyFiles,
  'file_too_large' => FeedbackError.fileTooLarge,
  'unknown_attachment' => FeedbackError.unknownAttachment,
  _ => FeedbackError.network,
};

/// Outcome of [FeedbackService.submit]. Deliberately not a thrown exception:
/// every failure here is one the sheet has copy for.
@immutable
class FeedbackResult {
  const FeedbackResult.ok() : error = null, failedFileName = null;
  const FeedbackResult.failed(this.error, {this.failedFileName});

  final FeedbackError? error;

  /// The attachment that could not be uploaded, when the failure names one.
  final String? failedFileName;

  bool get ok => error == null;
}

/// Sends in-app feedback: uploads each attachment straight to Convex file
/// storage, then records the report.
///
/// Both Convex functions it calls are public — a local-only account has no
/// backend user and must still be able to report a bug — so the client sends
/// its [ClientInfo] for triage and the backend attributes the row from the
/// Convex auth token when one is attached. Nothing here asserts an identity.
class FeedbackService {
  FeedbackService({
    required this.clientInfo,
    ConvexClient? client,
    http.Client? httpClient,
  }) : _client = client,
       _httpClient = httpClient;

  final ClientInfo clientInfo;

  // Resolved lazily so widget tests never require `ConvexClient.initialize()`.
  final ConvexClient? _client;
  ConvexClient get _resolvedClient => _client ?? ConvexClient.instance;

  final http.Client? _httpClient;

  /// Uploads [files] and records [text]. Uploads happen here rather than when a
  /// file is picked, so closing the sheet costs nothing — an abandoned draft
  /// leaves no bytes behind. The trade is that failing partway through a batch
  /// orphans the files already uploaded; nothing references them, and the
  /// backend's rate limits bound how many a client can create.
  Future<FeedbackResult> submit({
    required String text,
    required List<PlatformFile> files,
    String? locale,
  }) async {
    final httpClient = _httpClient ?? http.Client();
    final attachments = <Map<String, Object?>>[];
    try {
      for (final file in files) {
        final minted = await _mintUploadUrl();
        if (minted.error != null) {
          return FeedbackResult.failed(
            minted.error!,
            failedFileName: file.name,
          );
        }

        final storageId = await _uploadFile(
          httpClient,
          uploadUrl: minted.uploadUrl!,
          file: file,
        );
        if (storageId == null) {
          return FeedbackResult.failed(
            FeedbackError.uploadFailed,
            failedFileName: file.name,
          );
        }
        attachments.add({'storageId': storageId, 'filename': file.name});
      }

      final raw = await _resolvedClient.mutation(
        name: 'v1/feedback/mutations:submit',
        args: {
          'text': text,
          'attachments': attachments,
          'platform': clientInfo.platform,
          'appVersion': clientInfo.appVersion,
          'deviceId': clientInfo.deviceId,
          'locale': locale,
        },
      );
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) {
        return const FeedbackResult.failed(FeedbackError.network);
      }
      if (decoded['ok'] == true) return const FeedbackResult.ok();
      return FeedbackResult.failed(_errorFromWire(decoded['error']));
    } catch (e) {
      debugPrint('feedback: submit failed: $e');
      return const FeedbackResult.failed(FeedbackError.network);
    } finally {
      // Only close a client we created; an injected one belongs to the caller.
      if (_httpClient == null) httpClient.close();
    }
  }

  Future<_MintedUploadUrl> _mintUploadUrl() async {
    try {
      final raw = await _resolvedClient.mutation(
        name: 'v1/feedback/mutations:generateUploadUrl',
        args: {'deviceId': clientInfo.deviceId},
      );
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) {
        return _MintedUploadUrl.failed(FeedbackError.network);
      }
      if (decoded['ok'] != true) {
        return _MintedUploadUrl.failed(_errorFromWire(decoded['error']));
      }
      final url = decoded['uploadUrl'];
      if (url is! String || url.isEmpty) {
        return _MintedUploadUrl.failed(FeedbackError.network);
      }
      return _MintedUploadUrl.ok(url);
    } catch (e) {
      debugPrint('feedback: upload url failed: $e');
      return _MintedUploadUrl.failed(FeedbackError.network);
    }
  }

  /// POSTs one file's bytes at a Convex upload URL and returns the storage id
  /// Convex allocated, or null on any failure.
  ///
  /// The bytes go straight to Convex storage, never through a Convex function,
  /// so there is no 20 MB request ceiling here — only the product cap the
  /// backend re-checks against the stored size. Files are read one at a time,
  /// so peak memory is a single attachment rather than the whole batch.
  Future<String?> _uploadFile(
    http.Client httpClient, {
    required String uploadUrl,
    required PlatformFile file,
  }) async {
    try {
      final bytes = file.bytes ?? await _readBytes(file);
      if (bytes == null) return null;

      final response = await httpClient.post(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentTypeFor(file.name)},
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'feedback: upload rejected ${response.statusCode}: ${response.body}',
        );
        return null;
      }
      final decoded = decodeConvexResponse(response.body);
      if (decoded is! Map) return null;
      final storageId = decoded['storageId'];
      return storageId is String ? storageId : null;
    } catch (e) {
      debugPrint('feedback: upload of ${file.name} failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    final path = file.path;
    if (path == null) return null;
    return await File(path).readAsBytes();
  }
}

@immutable
class _MintedUploadUrl {
  const _MintedUploadUrl.ok(this.uploadUrl) : error = null;
  const _MintedUploadUrl.failed(this.error) : uploadUrl = null;

  final String? uploadUrl;
  final FeedbackError? error;
}

/// Content type for an upload, derived from the file's extension.
///
/// `PlatformFile` carries no MIME type, and Convex records whatever the upload
/// POST declares — so without this every attachment would be stored as an
/// opaque blob and a reviewer could not tell a screenshot from a log. The map
/// covers what people actually attach to a bug report; anything else uploads as
/// a generic binary, which is accurate rather than wrong.
String contentTypeFor(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot == -1 || dot == filename.length - 1) {
    return 'application/octet-stream';
  }
  final extension = filename.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'svg' => 'image/svg+xml',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'avi' => 'video/x-msvideo',
    'mkv' => 'video/x-matroska',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'pdf' => 'application/pdf',
    'txt' || 'log' => 'text/plain',
    'csv' => 'text/csv',
    'json' => 'application/json',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}
