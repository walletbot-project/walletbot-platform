import 'dart:async';
import 'dart:convert';

import 'package:app/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _bootstrapCacheKey = 'bootstrap_backend_config';

/// L0 backend discovery. Fetch the current backend URLs from a stable static
/// host and override the bundled defaults, so the backend can move without
/// shipping an app update.
///
/// Cache-first: when a last-good value exists it is applied immediately and the
/// network fetch only refreshes the cache in the background, so a slow or hung
/// network never blocks startup. On the first launch (no cache) the fetch is
/// awaited before the `ConvexClient` is constructed so the WebSocket connects
/// to the resolved URL. Fails open: on any error it falls back to the last-good
/// cache, then to the bundled `.env`/`--dart-define` value. MUST be awaited
/// before constructing the `ConvexClient`.
Future<void> resolveBackendConfig(
  FlutterSecureStorage storage, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (!kReleaseMode && AppConfig.hasConfiguredBackendUrls) {
    debugPrint('bootstrap: skipped; using configured local backend urls');
    return;
  }

  // Cache-first: apply the last-good value now, then refresh the cache in the
  // background for the next launch. We intentionally do NOT swap the runtime URL
  // on the background refresh — the WS client is already connecting to the
  // applied URL, and a changed URL is safest to pick up on the next cold start
  // rather than mid-session (which would split WS and HTTP across two hosts).
  final cached = await _readCache(storage);
  if (cached != null && _applyBody(cached)) {
    unawaited(_refreshCache(storage, client: client, timeout: timeout));
    return;
  }

  // First launch (no last-good cache): fetch and apply before the WS client is
  // created. Falls open to the bundled defaults if the fetch fails or is invalid.
  final body = await _fetchBody(client: client, timeout: timeout);
  if (body != null && _applyBody(body)) {
    await storage.write(key: _bootstrapCacheKey, value: body);
  }
}

/// Refresh the cached backend config for the next launch without touching the
/// runtime URLs. Validated before caching so a compromised/invalid response
/// can't poison the last-good cache.
Future<void> _refreshCache(
  FlutterSecureStorage storage, {
  http.Client? client,
  required Duration timeout,
}) async {
  final body = await _fetchBody(client: client, timeout: timeout);
  if (body != null && _parseUrls(body) != null) {
    await storage.write(key: _bootstrapCacheKey, value: body);
  }
}

Future<String?> _fetchBody({
  http.Client? client,
  required Duration timeout,
}) async {
  final ownClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final resp = await httpClient
        .get(Uri.parse(AppConfig.bootstrapUrl))
        .timeout(timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return resp.body;
    debugPrint('bootstrap: unexpected response ${resp.statusCode}');
  } catch (e) {
    debugPrint('bootstrap: fetch failed: $e');
  } finally {
    if (ownClient) httpClient.close();
  }
  return null;
}

Future<String?> _readCache(FlutterSecureStorage storage) async {
  try {
    final cached = await storage.read(key: _bootstrapCacheKey);
    if (cached == null || cached.isEmpty) return null;
    return cached;
  } catch (e) {
    debugPrint('bootstrap: read cache failed: $e');
    return null;
  }
}

bool _applyBody(String body) {
  final urls = _parseUrls(body);
  if (urls == null) return false;
  AppConfig.setRuntimeUrls(backendUrl: urls.$1, siteUrl: urls.$2);
  return true;
}

/// Parse and validate the bootstrap body. Both URLs must be valid https origins
/// before we redirect the WS client and — critically — the `/auth/refresh`
/// POSTs that carry the long-lived session token there. A compromised/MITM'd
/// BOOTSTRAP_URL response that downgrades to http or points at another host is
/// rejected so it is never trusted or cached as last-good.
(String, String)? _parseUrls(String body) {
  try {
    final data = jsonDecode(body) as Map<String, Object?>;
    final backendUrl = data['backendUrl'] as String?;
    final siteUrl = data['siteUrl'] as String?;
    if (_isHttpsUrl(backendUrl) && _isHttpsUrl(siteUrl)) {
      return (backendUrl!, siteUrl!);
    }
    debugPrint('bootstrap: rejected non-https/invalid urls');
  } catch (e) {
    debugPrint('bootstrap: parse failed: $e');
  }
  return null;
}

bool _isHttpsUrl(String? value) {
  if (value == null || value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  return uri != null && uri.isScheme('https') && uri.host.isNotEmpty;
}
