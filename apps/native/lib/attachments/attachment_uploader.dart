import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/convex/convex_client.dart';
import 'package:http/http.dart' as http;

import 'attachment_preparer.dart';
import 'attachment_types.dart';

/// Why an attachment could not be added, in the terms the screen has copy for.
enum AttachmentFailure {
  unsupportedType,
  tooLarge,
  rateLimited,

  /// The flag is off for this account, or the device id is unusable.
  unavailable,

  /// The request never reached the server.
  offline,
  failed,
}

class AttachmentUploadException implements Exception {
  AttachmentUploadException(this.failure, [this.cause]);

  final AttachmentFailure failure;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'AttachmentUploadException(${failure.name})'
      : 'AttachmentUploadException(${failure.name}, cause: $cause)';
}

/// The subset of `ConvexClient` this needs, so tests can stand in for it.
typedef AttachmentMutation =
    Future<Object?> Function(String name, Map<String, Object?> args);

/// The upload endpoint enforces two minutes server-side, like feedback.
const defaultAttachmentUploadTimeout = Duration(minutes: 2);

/// Uploads one prepared file straight to Convex storage and registers it,
/// like `uploadAttachment` on web. The bytes never pass through a Convex
/// function; `register` checks the stored file's own metadata.
///
/// Reachable by LOCAL accounts, whose Convex client carries no auth: the
/// device id identifies them, and a signed-in identity wins server-side.
class AttachmentUploader {
  AttachmentUploader({
    required this.deviceId,
    ConvexClient? client,
    AttachmentMutation? mutation,
    http.Client? httpClient,
    this.uploadTimeout = defaultAttachmentUploadTimeout,
  }) : assert(
         client != null || mutation != null,
         'provide a ConvexClient or a mutation stand-in',
       ),
       _mutation =
           mutation ?? ((name, args) => client!.mutation<Object?>(name, args)),
       _httpClient = httpClient ?? http.Client();

  final String deviceId;
  final Duration uploadTimeout;
  final AttachmentMutation _mutation;
  final http.Client _httpClient;

  Future<SentAttachment> upload(PreparedAttachment file) async {
    final url = await _call('v1/attachments/mutations:generateUploadUrl', {
      'deviceId': deviceId,
    });
    final uploadUrl = url['uploadUrl'];
    if (uploadUrl is! String || uploadUrl.isEmpty) {
      throw AttachmentUploadException(AttachmentFailure.failed);
    }

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(uploadUrl),
            headers: {'Content-Type': file.type.mimeType},
            body: file.bytes,
          )
          .timeout(uploadTimeout);
    } catch (error) {
      throw AttachmentUploadException(_transportFailureFor(error), error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AttachmentUploadException(
        AttachmentFailure.failed,
        'upload ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    final storageId = decoded is Map ? decoded['storageId'] : null;
    if (storageId is! String || storageId.isEmpty) {
      throw AttachmentUploadException(AttachmentFailure.failed);
    }

    final registered = await _call('v1/attachments/mutations:register', {
      'storageId': storageId,
      'name': file.name,
      'deviceId': deviceId,
    });
    final id = registered['attachmentId'];
    final kind = registered['kind'];
    if (id is! String || kind is! String) {
      throw AttachmentUploadException(AttachmentFailure.failed);
    }
    return SentAttachment(id: id, name: file.name, kind: kind);
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> args,
  ) async {
    final Object? decoded;
    try {
      decoded = await _mutation(name, args);
    } catch (error) {
      throw AttachmentUploadException(_transportFailureFor(error), error);
    }
    if (decoded is! Map<String, Object?>) {
      throw AttachmentUploadException(AttachmentFailure.failed);
    }
    if (decoded['ok'] != true) {
      throw AttachmentUploadException(
        _failureFor(decoded['error']),
        decoded['error'],
      );
    }
    return decoded;
  }

  AttachmentFailure _failureFor(Object? error) => switch (error) {
    'rate_limited' => AttachmentFailure.rateLimited,
    'feature_disabled' ||
    'unidentified_client' => AttachmentFailure.unavailable,
    'unsupported_type' => AttachmentFailure.unsupportedType,
    'too_large' => AttachmentFailure.tooLarge,
    _ => AttachmentFailure.failed,
  };

  AttachmentFailure _transportFailureFor(Object error) => switch (error) {
    TimeoutException() ||
    OperationTimeoutError() ||
    ConnectionLostError() ||
    IOException() ||
    http.ClientException() => AttachmentFailure.offline,
    _ => AttachmentFailure.failed,
  };
}
