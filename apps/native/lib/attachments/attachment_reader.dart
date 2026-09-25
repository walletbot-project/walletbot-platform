import 'dart:async';

import 'package:flutter/foundation.dart';

/// The subset of `ConvexClient.action` this needs, so tests can stand in.
typedef AttachmentReadAction =
    Future<Object?> Function(String name, Map<String, Object?> args);

/// Executes the agent's `readAttachment` tool: the one tool that needs the
/// network, injected into `ToolExecutors` by the Live command, which owns the
/// Convex client. The server returns a tool-ready result (a reading, or a
/// model-facing `error`), so it goes back to Gemini untouched.
class AttachmentReader {
  AttachmentReader({
    required this.action,
    required this.deviceId,
    required this.buildContext,
  });

  final AttachmentReadAction action;

  /// Identifies a local account, which has no Convex auth. A signed-in
  /// identity wins over it server-side.
  final String? deviceId;

  /// The reader's context: locale, timezone offset, default currency, the
  /// user's category names and the last turns of the conversation.
  final Future<Map<String, Object?>> Function() buildContext;

  static const failure = {
    'ok': false,
    'error': 'Reading the attachment failed',
  };

  Future<Map<String, dynamic>> read(Map<String, dynamic> args) async {
    final attachmentId = args['attachmentId'];
    final question = args['question'];
    if (attachmentId is! String ||
        attachmentId.isEmpty ||
        question is! String ||
        question.trim().isEmpty) {
      return {'ok': false, 'error': 'attachmentId and question are required'};
    }
    Map<String, Object?> context;
    try {
      context = await buildContext();
    } catch (error) {
      debugPrint('[attachments] read context failed: $error');
      context = const {};
    }
    try {
      final result = await action('v1/attachments/actions:read', {
        'attachmentId': attachmentId,
        'question': question,
        'deviceId': ?deviceId,
        'context': context,
      });
      if (result is Map) return result.cast<String, dynamic>();
      debugPrint('[attachments] unexpected read result: $result');
      return Map.of(failure);
    } catch (error) {
      debugPrint('[attachments] read failed: $error');
      return Map.of(failure);
    }
  }
}
