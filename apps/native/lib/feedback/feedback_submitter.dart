import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:http/http.dart' as http;

/// Why a submission failed, in the terms the sheet has copy for.
enum FeedbackFailure {
  /// The server's rate limit refused this device or user for now.
  rateLimited,

  /// The server rejected the attachments (too many, too large, unknown id).
  attachmentRejected,

  /// The message was empty or too long by the time it reached the server.
  messageInvalid,

  /// The request never reached the server: no network, a dropped socket, or a
  /// call that ran past its timeout. Worth its own case because the answer is
  /// "check your connection", not "something went wrong on our side".
  offline,

  /// Anything else: a rejected upload, an unexpected response shape.
  failed,
}

class FeedbackException implements Exception {
  FeedbackException(this.failure, [this.cause]);

  final FeedbackFailure failure;

  /// What this was classified from, kept so the caller can log it. The sheet
  /// shows [failure]; dropping the cause would leave a user-visible failure
  /// with no forensic trail at all.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'FeedbackException(${failure.name})'
      : 'FeedbackException(${failure.name}, cause: $cause)';
}

/// One file to attach, decoupled from `file_picker` so this layer (and its
/// tests) never needs the plugin. [openRead] is called once, and must stream
/// rather than buffer: an attachment can be 100 MB.
class FeedbackAttachment {
  const FeedbackAttachment({
    required this.name,
    required this.size,
    required this.openRead,
  });

  final String name;
  final int size;
  final Stream<List<int>> Function() openRead;
}

/// The subset of `ConvexClient` this needs, so tests can stand in for it.
/// Returns the mutation's already-decoded result.
typedef ConvexMutation =
    Future<Object?> Function(String name, Map<String, Object?> args);

/// How long a single attachment upload may run. The upload endpoint enforces
/// two minutes server-side, so the client gives up when the server would.
///
/// The Convex mutations get no deadline from here on purpose:
/// `ConvexClientConfig.defaultOperationTimeout` (30 s by default) already
/// bounds every call and throws [OperationTimeoutError] past it, which
/// [FeedbackFailure.offline] covers. A second, shorter deadline on top of it
/// only cancels calls that were still going to succeed.
const defaultFeedbackUploadTimeout = Duration(minutes: 2);

/// Sends one feedback submission: a short-lived upload URL per attachment, the
/// bytes POSTed straight to it, then a single mutation carrying only the storage
/// ids.
///
/// Files never travel through a Convex function. Uploads run one at a time on
/// purpose — every upload POST has a hard two-minute server-side timeout, which
/// ten parallel 100 MB uploads over one mobile connection would blow through.
///
/// Reachable by LOCAL-only accounts, whose Convex client carries no auth at all:
/// `deviceId` is what identifies them to the server's rate limiter. A signed-in
/// account's identity always wins over it server-side.
class FeedbackSubmitter {
  FeedbackSubmitter({
    required this.clientInfo,
    ConvexClient? client,
    ConvexMutation? mutation,
    http.Client? httpClient,
    this.uploadTimeout = defaultFeedbackUploadTimeout,
  }) : assert(
         client != null || mutation != null,
         'provide a ConvexClient or a mutation stand-in',
       ),
       _mutation =
           mutation ?? ((name, args) => client!.mutation<Object?>(name, args)),
       _httpClient = httpClient ?? http.Client();

  final ClientInfo clientInfo;
  final Duration uploadTimeout;
  final ConvexMutation _mutation;
  final http.Client _httpClient;

  /// Throws [FeedbackException] on every failure path, so the caller has one
  /// place to map to copy.
  Future<void> submit({
    required String message,
    required List<FeedbackAttachment> attachments,
    required String locale,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    final uploaded = <Map<String, Object?>>[];
    for (final (index, attachment) in attachments.indexed) {
      onUploadProgress?.call(index, attachments.length);
      final storageId = await _uploadAttachment(attachment);
      uploaded.add({'storageId': storageId, 'name': attachment.name});
    }
    onUploadProgress?.call(attachments.length, attachments.length);

    final response = await _call('v1/feedback/mutations:submit', {
      'message': message,
      'attachments': uploaded,
      'platform': clientInfo.platform,
      'appVersion': clientInfo.appVersion,
      'locale': locale,
      'deviceId': clientInfo.deviceId,
    });
    if (response['ok'] != true) {
      throw FeedbackException(_failureFor(response['error']));
    }
  }

  Future<String> _uploadAttachment(FeedbackAttachment attachment) async {
    final response = await _call(
      'v1/feedback/mutations:generateAttachmentUploadUrl',
      {'deviceId': clientInfo.deviceId},
    );
    if (response['ok'] != true) {
      throw FeedbackException(_failureFor(response['error']));
    }
    final uploadUrl = response['uploadUrl'];
    if (uploadUrl is! String || uploadUrl.isEmpty) {
      throw FeedbackException(FeedbackFailure.failed);
    }

    final request = http.StreamedRequest('POST', Uri.parse(uploadUrl))
      ..contentLength = attachment.size;
    final contentType = contentTypeForFileName(attachment.name);
    if (contentType != null) {
      request.headers['Content-Type'] = contentType;
    }
    // Pumped into the request body as it is read: never the whole file in
    // memory at once. Held so a timed-out upload stops reading the file
    // instead of draining 100 MB into a request nobody is waiting for.
    final pump = attachment.openRead().listen(
      request.sink.add,
      onError: request.sink.addError,
      onDone: request.sink.close,
      cancelOnError: true,
    );

    final String body;
    final http.StreamedResponse uploadResponse;
    try {
      uploadResponse = await _httpClient.send(request).timeout(uploadTimeout);
      body = await uploadResponse.stream.bytesToString().timeout(uploadTimeout);
    } catch (error) {
      await pump.cancel();
      throw FeedbackException(_transportFailureFor(error), error);
    }
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw FeedbackException(FeedbackFailure.failed);
    }
    final storageId = (jsonDecode(body) as Map<String, Object?>)['storageId'];
    if (storageId is! String || storageId.isEmpty) {
      throw FeedbackException(FeedbackFailure.failed);
    }
    return storageId;
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> args,
  ) async {
    final Object? decoded;
    try {
      decoded = await _mutation(name, args);
    } catch (error) {
      throw FeedbackException(_transportFailureFor(error), error);
    }
    if (decoded is! Map<String, Object?>) {
      throw FeedbackException(FeedbackFailure.failed);
    }
    return decoded;
  }

  FeedbackFailure _failureFor(Object? error) => switch (error) {
    'rate_limited' => FeedbackFailure.rateLimited,
    'attachment_invalid' => FeedbackFailure.attachmentRejected,
    'message_invalid' => FeedbackFailure.messageInvalid,
    _ => FeedbackFailure.failed,
  };

  /// Tells "the request never got out" apart from "the server said no", so the
  /// sheet can point at the connection instead of blaming the submission.
  FeedbackFailure _transportFailureFor(Object error) => switch (error) {
    TimeoutException() ||
    OperationTimeoutError() ||
    ConnectionLostError() ||
    IOException() ||
    http.ClientException() => FeedbackFailure.offline,
    _ => FeedbackFailure.failed,
  };
}

/// A best-effort content type from the file extension, so a screenshot is still
/// viewable in the Convex dashboard. `file_picker` reports no MIME type, and
/// guessing beyond this short list is not worth a dependency: Convex simply
/// stores no content type when the header is absent.
String? contentTypeForFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' || 'log' => 'text/plain',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'zip' => 'application/zip',
    _ => null,
  };
}
