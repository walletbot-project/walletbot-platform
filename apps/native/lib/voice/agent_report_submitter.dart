import 'dart:async';
import 'dart:io';

import 'package:app/app_config/client_info.dart';
import 'package:app/sync/wire.dart';
import 'package:convex_flutter/convex_flutter.dart';

/// Why a report failed, in the terms the sheet has copy for.
enum AgentReportFailure {
  /// The server's rate limit refused this device or user for now.
  rateLimited,

  /// The server rejected the payload: an unknown reason or scope, or a
  /// response-scoped report with nothing to look at.
  invalid,

  /// The request never reached the server: no network, a dropped socket, or a
  /// call that ran past its timeout. Worth its own case because the answer is
  /// "check your connection", not "something went wrong on our side".
  offline,

  /// Anything else: an unexpected response shape.
  failed,
}

class AgentReportException implements Exception {
  AgentReportException(this.failure, [this.cause]);

  final AgentReportFailure failure;

  /// What this was classified from, kept so the caller can log it. The sheet
  /// shows [failure]; dropping the cause would leave a user-visible failure
  /// with no forensic trail at all.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'AgentReportException(${failure.name})'
      : 'AgentReportException(${failure.name}, cause: $cause)';
}

/// What the report points at. `response` carries the flagged turn's text;
/// `session` names the conversation instead, for a reply that was voice-only or
/// has already scrolled away.
enum AgentReportScope { response, session }

/// The subset of `ConvexClient` this needs, so tests can stand in for it.
typedef ConvexMutation =
    Future<String> Function({
      required String name,
      required Map<String, dynamic> args,
    });

/// Sends one report of an agent response.
///
/// Reachable by LOCAL-only accounts, whose Convex client carries no auth at
/// all: `deviceId` is what identifies them to the server's rate limiter, and a
/// signed-in account's identity always wins over it server-side. That matters
/// here more than it does for feedback — Google Play requires the reporting path
/// to work for every user of the app, and a local account is still a user.
class AgentReportSubmitter {
  AgentReportSubmitter({required this.clientInfo, ConvexMutation? mutation})
    : _mutation = mutation ?? _defaultMutation;

  final ClientInfo clientInfo;
  final ConvexMutation _mutation;

  static Future<String> _defaultMutation({
    required String name,
    required Map<String, dynamic> args,
  }) => ConvexClient.instance.mutation(name: name, args: args);

  /// Throws [AgentReportException] on every failure path, so the caller has one
  /// place to map to copy.
  Future<void> submit({
    required String reason,
    required AgentReportScope scope,
    required String locale,
    String? note,
    String? reportedText,
    String? precedingUserText,
    String? sessionId,
    String? model,
    DateTime? occurredAt,
  }) async {
    final response = await _call('v1/agentReports/mutations:submit', {
      'reason': reason,
      'scope': scope.name,
      if (note != null && note.isNotEmpty) 'note': note,
      if (reportedText != null && reportedText.isNotEmpty)
        'reportedText': reportedText,
      if (precedingUserText != null && precedingUserText.isNotEmpty)
        'precedingUserText': precedingUserText,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      if (model != null && model.isNotEmpty) 'model': model,
      if (occurredAt != null)
        'occurredAt': BigInt.from(occurredAt.millisecondsSinceEpoch),
      'platform': clientInfo.platform,
      'appVersion': clientInfo.appVersion,
      'locale': locale,
      'deviceId': clientInfo.deviceId,
    });
    if (response['ok'] != true) {
      throw AgentReportException(_failureFor(response['error']));
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> args,
  ) async {
    final String raw;
    try {
      raw = await _mutation(
        name: name,
        args: prepareArgValue(args) as Map<String, dynamic>,
      );
    } catch (error) {
      throw AgentReportException(_transportFailureFor(error), error);
    }
    final decoded = decodeConvexResponse(raw);
    if (decoded is! Map<String, Object?>) {
      throw AgentReportException(AgentReportFailure.failed);
    }
    return decoded;
  }

  AgentReportFailure _failureFor(Object? error) => switch (error) {
    'rate_limited' => AgentReportFailure.rateLimited,
    'reason_invalid' ||
    'scope_invalid' ||
    'report_invalid' => AgentReportFailure.invalid,
    _ => AgentReportFailure.failed,
  };

  /// Tells "the request never got out" apart from "the server said no", so the
  /// sheet can point at the connection instead of blaming the report.
  AgentReportFailure _transportFailureFor(Object error) => switch (error) {
    TimeoutException() || IOException() => AgentReportFailure.offline,
    _ => AgentReportFailure.failed,
  };
}
