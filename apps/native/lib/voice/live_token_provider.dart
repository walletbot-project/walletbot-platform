import 'dart:convert';
import 'package:http/http.dart' as http;
import '../convex/convex_client.dart';
import 'agent_generated.dart';
import 'live_protocol.dart';

/// One-shot fetch of a constrained Gemini Live token from the backend,
/// shared by the command's connect path and the factory's prefetch.
///
/// Nothing about starting a voice session waits on the Convex socket. The
/// action rides that socket, which can itself be mid-reconnect exactly when a
/// voice reconnect needs a token (network loss, resume from background), so
/// it is bounded to 6 s *and* runs as a one-shot HTTP POST whenever the
/// socket is not ready, rather than queueing behind the reconnect. The
/// `/v1/live/token` endpoint below is the last resort and is independent of
/// the Convex client entirely.
/// The backend refused to mint (`live/helpers.ts:LiveTokenError`). Permanent
/// for this session: the reconnect backoff cannot turn a rate limit or an
/// unusable identity into a token, it only burns more of the caller's budget.
class LiveTokenRefusedException implements Exception {
  const LiveTokenRefusedException(this.reason, {this.retryAfter});

  /// Server-side reason: `rate_limited` or `unidentified_client`.
  final String reason;
  final Duration? retryAfter;

  @override
  String toString() =>
      'Live token refused: $reason'
      '${retryAfter == null ? '' : ' (retry after ${retryAfter!.inSeconds}s)'}';
}

/// Nothing to authenticate the mint with: no bundled token or key, and no
/// identity the backend would accept. Also permanent for this session.
class MissingLiveCredentialsException implements Exception {
  const MissingLiveCredentialsException();

  @override
  String toString() =>
      'Missing Gemini credentials. Configure a Convex account or device id, '
      'or GEMINI_LIVE_TOKEN.';
}

/// Reads a structured refusal out of a mint response. `retryAfter` is the
/// rate limiter's millisecond hint.
LiveTokenRefusedException? _refusalFrom(Map<String, Object?> body) {
  final error = body['error'];
  if (error is! String || error.isEmpty) return null;
  final retryAfter = body['retryAfter'];
  return LiveTokenRefusedException(
    error,
    retryAfter: retryAfter is num
        ? Duration(milliseconds: retryAfter.round())
        : null,
  );
}

/// Turns a non-2xx mint response into the most specific error available: a
/// structured refusal when the body carries one, the raw status otherwise.
Object _httpFailure(int statusCode, String rawBody) {
  try {
    final decoded = jsonDecode(rawBody);
    if (decoded is Map) {
      final refusal = _refusalFrom(decoded.cast<String, Object?>());
      if (refusal != null) return refusal;
    }
  } on FormatException {
    // Not JSON (a proxy error page, an empty body): fall through to the raw
    // status, which is more useful than hiding it behind a parse failure.
  }
  return StateError('Convex live token request failed: $statusCode $rawBody');
}

Future<LiveToken> fetchLiveToken({
  required bool useAuthenticatedTokenAction,
  required ConvexClient? convexClient,
  required String? sessionToken,
  required String? deviceId,
  required String convexSiteUrl,
  String? localAccountId,
  Future<Map<String, Object?>> Function()? buildMintArgs,
  void Function(String phase, Map<String, Object?> extra)? onPhase,

  /// `'manual'` or `'auto'` (`VoiceConversationMode.turnDetection`). Null
  /// leaves the server default, which is what builds before it got.
  String? turnDetection,
}) async {
  final fetchStopwatch = Stopwatch()..start();
  // The mint args (platform identity, locale/timezone, USER_CONTEXT snapshot)
  // are best-effort: a failed build must never block the token fetch.
  Map<String, Object?> mintArgs = const {};
  if (buildMintArgs != null) {
    try {
      mintArgs = await buildMintArgs();
    } catch (e) {
      onPhase?.call('mint_args_failed', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'error': e.toString(),
      });
    }
  }
  if (turnDetection != null) {
    mintArgs = {...mintArgs, 'turnDetection': turnDetection};
  }
  Map<String, Object?>? body;
  var via = 'http_endpoint';
  if (useAuthenticatedTokenAction && convexClient != null) {
    final status = convexClient.currentConnectionState.status;
    final ready = status == ConnectionStatus.ready;
    onPhase?.call('token_action_start', {
      'elapsedMs': fetchStopwatch.elapsedMilliseconds,
      'connection': status.name,
      'transport': ready ? 'convex_ws' : 'convex_http',
    });
    try {
      final decoded = await convexClient.action<Object?>(
        'v1/live/actions:requestLiveToken',
        mintArgs,
        options: const CallOptions(
          operationTimeout: Duration(seconds: 6),
          httpFallback: HttpFallback.whenNotReady,
        ),
      );
      if (decoded is! Map) {
        throw StateError('Malformed Convex live token response');
      }
      body = decoded.cast<String, Object?>();
      via = ready ? 'convex_ws' : 'convex_http';
    } catch (error) {
      onPhase?.call('token_action_failed', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'connection': status.name,
        'error': error.toString(),
      });
    }
  }
  if (body == null) {
    if (convexSiteUrl.isEmpty) {
      onPhase?.call('token_unavailable', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'reason': 'no_site_url',
      });
      return const LiveToken('');
    }
    // The endpoint takes either identity. A local account has no session and
    // mints against its device id instead, which is the whole reason the agent
    // works without an account; a signed-in caller sends both and the server
    // lets the session win.
    final credential = sessionToken;
    final device = deviceId?.trim() ?? '';
    if ((credential == null || credential.isEmpty) && device.isEmpty) {
      onPhase?.call('token_unavailable', {
        'elapsedMs': fetchStopwatch.elapsedMilliseconds,
        'reason': 'unidentified_client',
      });
      return const LiveToken('');
    }
    final base = Uri.parse(convexSiteUrl);
    final response = await http
        .post(
          base.replace(path: '/v1/live/token'),
          headers: {
            if (credential != null && credential.isNotEmpty)
              'Authorization': 'Bearer $credential',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            ...mintArgs,
            if (device.isNotEmpty) 'deviceId': device,
            'localAccountId': ?localAccountId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailure(response.statusCode, response.body);
    }
    body = (jsonDecode(response.body) as Map).cast<String, Object?>();
  }

  // A refusal can arrive with a 200 from the Convex action or a 4xx from the
  // endpoint; both land here as a permanent error rather than a retry.
  final refusal = _refusalFrom(body);
  if (refusal != null) throw refusal;

  final model = body['model'];
  if (model != kAgentModel && model != LiveToken.legacyModel) {
    throw const LiveTokenRefusedException('model_mismatch');
  }
  final token = body['token'];
  if (token is! String || token.isEmpty) {
    throw StateError('Convex live token response did not include token');
  }
  onPhase?.call('token_received', {
    'elapsedMs': fetchStopwatch.elapsedMilliseconds,
    // Which transport actually served it. A session that starts slowly is a
    // different bug depending on this: `convex_ws` points at the socket,
    // `http_endpoint` means the Convex action failed outright.
    'via': via,
    'model': body['model']?.toString(),
    // Server-reported breakdown (google round trip, mint total, cold-start
    // module age, action/http totals): elapsedMs minus the server total is
    // network + Convex routing.
    if (body['timings'] is Map) 'server': body['timings'],
  });
  return LiveToken(token, model: model as String);
}
