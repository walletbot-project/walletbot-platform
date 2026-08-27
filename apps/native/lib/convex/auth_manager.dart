import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';

import 'protocol.dart';

/// Fetches a JWT. `forceRefresh` means "do not return a cached token".
/// Returning null means auth is intentionally unavailable (signed out).
/// Throwing means the fetch transiently failed (network, server error).
typedef TokenFetcher = Future<String?> Function({required bool forceRefresh});

enum AuthState { unauthenticated, authenticating, authenticated, refreshFailed }

class _PendingConfirmation {
  _PendingConfirmation({required this.baseVersion, required this.wasFresh});
  final int baseVersion;
  final bool wasFresh;
}

/// Token fetch/refresh scheduling and the AuthError state machine
/// (≈ convex-js `authentication_manager.ts`, docs/dart-convex-client.md §6).
///
/// The invariant that kills the stale-token reconnect loop (LESSONS.md #1/#12):
/// a reconnect never re-presents a token the server already saw — every
/// restart fetches with `forceRefresh: true`. After [maxFreshFailures]
/// consecutive failures to present a fresh token, the manager gives up,
/// downgrades to unauthenticated (`tokenType: "None"`), keeps the socket
/// connected, and retries on a timer instead of looping.
class AuthManager {
  AuthManager({
    required this.sendMessage,
    required this.canSendNow,
    required this.restartSocket,
    required this.pauseSocket,
    required this.resumeSocket,
    required this.onStateChange,
    required this.emitEvent,
    this.refreshLeeway = const Duration(seconds: 60),
    this.maxFreshFailures = 2,
    this.retryInterval = const Duration(seconds: 60),
    this.fetchTimeout = const Duration(seconds: 15),
  });

  final void Function(ClientMessage message) sendMessage;

  /// Whether an Authenticate can be delivered right now (socket open).
  final bool Function() canSendNow;
  final void Function(String reason) restartSocket;
  final void Function() pauseSocket;
  final void Function() resumeSocket;
  final void Function(AuthState state) onStateChange;
  final void Function(String type, Map<String, Object?> data) emitEvent;

  /// Refresh this long before the token's `exp`.
  final Duration refreshLeeway;

  /// Consecutive fresh-token failures before downgrading to unauthenticated.
  final int maxFreshFailures;

  /// How often to retry after downgrading.
  final Duration retryInterval;

  /// Timebox on every fetcher call. A hung fetch would otherwise poison the
  /// coalesced in-flight future forever and park restarts in `connecting`.
  final Duration fetchTimeout;

  TokenFetcher? _fetcher;
  String? _token;
  DateTime? _tokenExp;

  /// Local identity version: the next Authenticate's baseVersion. Resets to 0
  /// per socket (§A.5).
  int _identityVersion = 0;
  _PendingConfirmation? _pending;
  int _freshFailures = 0;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  Future<String?>? _fetchInFlight;
  bool _fetchInFlightForced = false;
  bool _initialFlowRunning = false;
  bool _disposed = false;

  AuthState _state = AuthState.unauthenticated;
  AuthState get state => _state;

  bool get hasFetcher => _fetcher != null;

  /// True while an Authenticate awaits server confirmation — used by the
  /// client to include auth in the "fully resynced" check.
  bool get awaitingConfirmation => _pending != null;

  void _setState(AuthState next) {
    if (_state == next) return;
    _state = next;
    emitEvent('auth.state', {'state': next.name});
    onStateChange(next);
  }

  /// Installs the token fetcher (§6.1). If the socket is ready, pauses
  /// outgoing traffic, authenticates with a cached token, and resumes;
  /// otherwise the next restart authenticates.
  void setAuth(TokenFetcher fetcher) {
    _fetcher = fetcher;
    _freshFailures = 0;
    _retryTimer?.cancel();
    _setState(AuthState.authenticating);
    ensureAuthenticated();
  }

  /// Runs the initial auth flow if a fetcher is installed but this socket has
  /// no Authenticate confirmed or pending — covers setAuth arriving while a
  /// restart was already past its auth step.
  void ensureAuthenticated() {
    if (_fetcher == null || _disposed) return;
    if (_pending != null) return;
    if (_state == AuthState.authenticated ||
        _state == AuthState.refreshFailed) {
      return;
    }
    if (!canSendNow() || _initialFlowRunning) return;
    unawaited(_initialAuthFlow());
  }

  Future<void> _initialAuthFlow() async {
    _initialFlowRunning = true;
    pauseSocket();
    try {
      var token = await _fetch(forceRefresh: false);
      if (token != null && _isExpired(token)) {
        token = await _fetch(forceRefresh: true);
      }
      if (_disposed || _fetcher == null) return;
      if (token == null) {
        _setState(AuthState.unauthenticated);
        return;
      }
      if (canSendNow()) _sendAuthenticate(token, wasFresh: false);
    } catch (error) {
      emitEvent('auth.fetchFailed', {'phase': 'setAuth', 'error': '$error'});
      _recordFreshFailure('setAuth fetch: $error');
    } finally {
      _initialFlowRunning = false;
      resumeSocket();
    }
  }

  /// Removes auth (§5.3 `clearAuth`).
  void clearAuth() {
    _fetcher = null;
    _token = null;
    _tokenExp = null;
    _pending = null;
    _freshFailures = 0;
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    if (canSendNow()) {
      sendMessage(
        AuthenticateMessage(token: null, baseVersion: _identityVersion),
      );
      _identityVersion++;
    }
    _setState(AuthState.unauthenticated);
  }

  /// Restart sequence step 2 (§5.2): resets per-socket identity state and
  /// returns the Authenticate to send — always with a fresh token, never one
  /// the server may have already rejected (§6.3). Null when unauthenticated
  /// or the fetch failed (the socket then runs unauthenticated and the retry
  /// timer keeps trying).
  Future<AuthenticateMessage?> restartAuthenticate() async {
    _identityVersion = 0;
    _pending = null;
    _refreshTimer?.cancel();
    final fetcher = _fetcher;
    if (fetcher == null) return null;
    _setState(AuthState.authenticating);
    try {
      final token = await _fetch(forceRefresh: true);
      if (_disposed || _fetcher == null) return null;
      if (token == null) {
        _setState(AuthState.unauthenticated);
        return null;
      }
      _pending = _PendingConfirmation(baseVersion: 0, wasFresh: true);
      _identityVersion = 1;
      emitEvent('auth.sent', {'baseVersion': 0, 'fresh': true});
      return AuthenticateMessage(token: token, baseVersion: 0);
    } catch (error) {
      emitEvent('auth.fetchFailed', {'phase': 'restart', 'error': '$error'});
      _recordFreshFailure('restart fetch: $error');
      return null;
    }
  }

  void _sendAuthenticate(String token, {required bool wasFresh}) {
    final baseVersion = _identityVersion;
    _pending = _PendingConfirmation(
      baseVersion: baseVersion,
      wasFresh: wasFresh,
    );
    _identityVersion++;
    emitEvent('auth.sent', {'baseVersion': baseVersion, 'fresh': wasFresh});
    sendMessage(AuthenticateMessage(token: token, baseVersion: baseVersion));
  }

  /// Called for every Transition (§A.5: an identity advance is the server's
  /// auth confirmation — there is no dedicated auth-OK message).
  void onTransition(StateVersion startVersion, StateVersion endVersion) {
    if (endVersion.identity <= startVersion.identity) return;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _freshFailures = 0;
    _retryTimer?.cancel();
    _setState(AuthState.authenticated);
    emitEvent('auth.confirmed', {'identity': endVersion.identity});
    if (!pending.wasFresh) {
      // §6.2: the cached token is confirmed; upgrade to a fresh one right
      // away so the scheduled refresh starts from a known-new token.
      unawaited(
        _fetchFreshAndAuthenticate(trigger: 'upgradeAfterCachedConfirm'),
      );
    } else {
      _scheduleRefresh();
    }
  }

  /// The three-way AuthError filter (§6.4).
  void onAuthError(AuthErrorMessage message) {
    final latestBase = _identityVersion - 1;
    if (!message.authUpdateAttempted && _pending != null) {
      // A query ran with the dying token while a newer token is already
      // awaiting confirmation — not our problem.
      emitEvent('auth.errorIgnored', {
        'reason': 'queryRanWithDyingToken',
        'error': message.error,
      });
      return;
    }
    final baseVersion = message.baseVersion;
    if (baseVersion != null && baseVersion < latestBase) {
      emitEvent('auth.errorIgnored', {
        'reason': 'staleBaseVersion',
        'baseVersion': baseVersion,
        'latest': latestBase,
      });
      return;
    }
    final rejectedFresh = _pending?.wasFresh ?? true;
    _pending = null;
    // The server did not apply the rejected Authenticate, so its identity
    // version did not advance: roll the local counter back so a follow-up
    // Authenticate (e.g. the tokenType None downgrade) carries the right
    // baseVersion.
    if (baseVersion != null) {
      _identityVersion = baseVersion;
    } else if (_identityVersion > 0) {
      _identityVersion--;
    }
    emitEvent('auth.error', {
      'error': message.error,
      'baseVersion': baseVersion,
      'rejectedFresh': rejectedFresh,
    });
    if (rejectedFresh) {
      _recordFreshFailure('server rejected fresh token: ${message.error}');
      if (_freshFailures >= maxFreshFailures) return; // downgraded, no restart
    }
    // Stop the socket so queued mutations can't fire with bad auth; the
    // restart fetches fresh and re-authenticates.
    restartSocket('AuthError');
  }

  void _recordFreshFailure(String detail) {
    _freshFailures++;
    emitEvent('auth.freshFailure', {
      'count': _freshFailures,
      'max': maxFreshFailures,
      'detail': detail,
    });
    if (_freshFailures >= maxFreshFailures &&
        _state != AuthState.refreshFailed) {
      // §6.4: give up — run connected-but-unauthenticated, let the app
      // decide what to show, and keep retrying on a timer instead of
      // reconnecting.
      if (canSendNow()) {
        sendMessage(
          AuthenticateMessage(token: null, baseVersion: _identityVersion),
        );
        _identityVersion++;
      }
      _setState(AuthState.refreshFailed);
    }
    _scheduleRetry();
  }

  Future<void> _fetchFreshAndAuthenticate({required String trigger}) async {
    if (_fetcher == null || _disposed) return;
    try {
      final token = await _fetch(forceRefresh: true);
      if (_disposed || _fetcher == null) return;
      if (token == null) {
        _setState(AuthState.unauthenticated);
        return;
      }
      if (canSendNow()) {
        _sendAuthenticate(token, wasFresh: true);
      }
    } catch (error) {
      emitEvent('auth.fetchFailed', {'phase': trigger, 'error': '$error'});
      _recordFreshFailure('$trigger fetch: $error');
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final exp = _tokenExp;
    if (exp == null) return;
    var delay = exp.difference(clock.now()) - refreshLeeway;
    if (delay < Duration.zero) delay = Duration.zero;
    emitEvent('auth.refreshScheduled', {'inMs': delay.inMilliseconds});
    _refreshTimer = Timer(delay, () {
      unawaited(_fetchFreshAndAuthenticate(trigger: 'scheduledRefresh'));
    });
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    emitEvent('auth.retryScheduled', {'inMs': retryInterval.inMilliseconds});
    _retryTimer = Timer(retryInterval, () {
      if (_fetcher == null || _disposed) return;
      unawaited(_fetchFreshAndAuthenticate(trigger: 'retryTimer'));
    });
  }

  /// A valid (unexpired) token for out-of-band HTTP use — the voice token
  /// fetch and TelemetryClient stop re-minting JWTs per batch (§6.5).
  Future<String?> validToken() async {
    final token = _token;
    final exp = _tokenExp;
    if (token != null &&
        (exp == null ||
            exp.isAfter(clock.now().add(const Duration(seconds: 30))))) {
      return token;
    }
    if (_fetcher == null) return null;
    try {
      return await _fetch(forceRefresh: false);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetch({required bool forceRefresh}) async {
    // Coalesce concurrent fetches; a forced fetch never reuses a non-forced
    // one already in flight.
    final inFlight = _fetchInFlight;
    if (inFlight != null && (_fetchInFlightForced || !forceRefresh)) {
      return inFlight;
    }
    final fetcher = _fetcher;
    if (fetcher == null) return null;
    emitEvent('auth.fetchStart', {'forceRefresh': forceRefresh});
    final future = fetcher(forceRefresh: forceRefresh).timeout(fetchTimeout);
    _fetchInFlight = future;
    _fetchInFlightForced = forceRefresh;
    try {
      final token = await future;
      _token = token;
      _tokenExp = token == null ? null : _parseJwtExp(token);
      emitEvent('auth.fetched', {
        'hasToken': token != null,
        'exp': _tokenExp?.toIso8601String(),
      });
      return token;
    } finally {
      if (identical(_fetchInFlight, future)) _fetchInFlight = null;
    }
  }

  bool _isExpired(String token) {
    final exp = _parseJwtExp(token);
    if (exp == null) return false;
    return !exp.isAfter(clock.now().add(refreshLeeway));
  }

  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
  }

  static DateTime? _parseJwtExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = (payload as Map)['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
    } catch (_) {
      return null;
    }
  }
}
