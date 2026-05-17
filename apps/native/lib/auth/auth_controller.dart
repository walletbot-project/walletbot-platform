import 'dart:async';
import 'dart:convert';

import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class AuthController extends ChangeNotifier {
  AuthController({http.Client? httpClient, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _http = httpClient ?? http.Client();

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';
  // Refresh the access token this far before its server-issued expiry. Picked
  // so that with the (eventual) 15 min access TTL we refresh every ~10 min;
  // with the current 60 s TTL we always refresh on demand. The session token
  // doesn't rotate, so calling /auth/refresh frequently is idempotent.
  static const _refreshLeeway = Duration(minutes: 5);

  final FlutterSecureStorage _storage;
  final http.Client _http;

  List<UserAccount> _accounts = const [];
  String? _activeId;
  Timer? _refreshTimer;
  Future<bool>? _refreshInFlight;
  Future<void> _persistQueue = Future.value();

  List<UserAccount> get accounts => List.unmodifiable(_accounts);
  String? get activeId => _activeId;
  UserAccount? get activeAccount {
    if (_activeId == null) return null;
    for (final a in _accounts) {
      if (a.id == _activeId) return a;
    }
    return null;
  }

  Future<void> load() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<Object?>;
      _accounts = list
          .map((e) => UserAccount.fromJson(e as Map<String, Object?>))
          .toList();
    }
    _activeId = await _storage.read(key: _activeIdKey);
    final a = activeAccount;
    await _applyConvexAuth(a?.accessToken);
    if (a != null && a.type == AccountType.remote) {
      _scheduleNextRefresh();
    }
    notifyListeners();
  }

  /// Sign in with Google → POST idToken to backend, store the access/refresh
  /// pair, prime Convex auth. Backend handles user upsert via better-auth's
  /// adapter so the same user record is shared with the web app.
  Future<UserAccount> signInWithGoogle() async {
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in returned no idToken');
    }

    final body = await _postJson('/auth/google', {'idToken': idToken});
    final userJson = body['user'] as Map<String, Object?>?;
    if (userJson == null) {
      throw StateError('Sign-in response missing user');
    }

    final account = UserAccount(
      id: userJson['id'] as String,
      type: AccountType.remote,
      name: userJson['name'] as String?,
      email: userJson['email'] as String?,
      picture: userJson['image'] as String?,
      accessToken: body['accessToken'] as String,
      accessTokenExpiresAt: (body['accessTokenExpiresAt'] as num).toInt(),
      refreshToken: body['refreshToken'] as String,
    );

    _accounts = [
      for (final a in _accounts)
        if (a.id != account.id) a,
      account,
    ];
    _activeId = account.id;
    await _persist();
    await _applyConvexAuth(account.accessToken);
    _scheduleNextRefresh();
    notifyListeners();
    return account;
  }

  /// Opportunistic refresh — called on app resume. Cheap when the access token
  /// is still fresh; forces a refresh otherwise. Never deletes local data.
  Future<void> refreshActiveSession() async {
    final active = activeAccount;
    if (active == null || active.type != AccountType.remote) return;
    final exp = active.accessTokenExpiresAt;
    if (exp != null) {
      final remaining = exp - DateTime.now().millisecondsSinceEpoch;
      if (remaining > _refreshLeeway.inMilliseconds) {
        _scheduleNextRefresh();
        return;
      }
    }
    await _refreshAccessToken();
  }

  /// Wraps a Convex call so that:
  ///   - on "Unauthenticated" we refresh the access token and retry once
  ///     (catches the race where exp slips through);
  ///   - on [TimeoutException] (zombie WebSocket — Android froze it during
  ///     background, `connectionState` may still say `connected`) we force a
  ///     `ConvexClient.reconnect()` and retry once.
  Future<T> runConvexAuthenticated<T>(Future<T> Function() fn) async {
    await _ensureFreshAuth();
    try {
      return await fn();
    } on ClientError catch (e) {
      if (!_isAuthError(_clientErrorMessage(e))) rethrow;
      final ok = await _refreshAccessToken();
      if (!ok) rethrow;
      return await fn();
    } on TimeoutException {
      await ConvexClient.instance.reconnect();
      return await fn();
    }
  }

  /// Pre-flight check before any authenticated Convex call:
  ///   1. wait for any in-flight refresh so we don't fire with a token that's
  ///      already being rotated out;
  ///   2. if the access token is already past (or within leeway of) its server-
  ///      issued exp, force a refresh now and wait for it.
  ///
  /// Needed because OS background suspension stops our refresh timer. Without
  /// this, the first call after resume can fire with an expired token.
  Future<void> _ensureFreshAuth() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
    }
    final active = activeAccount;
    if (active == null || active.type != AccountType.remote) return;
    final exp = active.accessTokenExpiresAt;
    if (exp == null) return;
    final remaining = exp - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= _refreshLeeway.inMilliseconds) {
      await _refreshAccessToken();
    }
  }

  /// Subscribes to a Convex query and survives JWT swaps via [_applyConvexAuth].
  /// If the backend reports auth failure we refresh once and re-subscribe under
  /// the same handle; callers should never see the underlying handle change.
  ///
  /// Caller owns the returned handle and MUST call [ConvexSubscriptionHandle.cancel]
  /// when no longer needed (typically in widget `dispose`).
  Future<ConvexSubscriptionHandle> subscribeConvex({
    required String name,
    required Map<String, dynamic> args,
    required FutureOr<void> Function(String) onUpdate,
  }) async {
    final wrapper = ConvexSubscriptionHandle._();
    var retried = false;

    Future<void> doSubscribe() async {
      if (wrapper._cancelled) return;
      await _ensureFreshAuth();
      if (wrapper._cancelled) return;
      late SubscriptionHandle handle;
      try {
        handle = await ConvexClient.instance.subscribe(
          name: name,
          args: args,
          onUpdate: (value) async {
            if (wrapper._cancelled || wrapper._current != handle) return;
            retried = false;
            await onUpdate(value);
          },
          onError: (message, value) async {
            if (wrapper._cancelled || wrapper._current != handle) return;
            if (_isAuthError(message)) {
              if (retried) {
                debugPrint(
                  'subscribeConvex($name): auth error after retry — giving up',
                );
                return;
              }
              retried = true;
              handle.cancel();
              wrapper._current = null;
              await _refreshAccessToken();
              await doSubscribe();
              return;
            }
            debugPrint(
              'subscribeConvex($name): error: $message ${value ?? ""}',
            );
          },
        );
      } on TimeoutException {
        // Zombie WebSocket — force a healthcheck round-trip and retry once.
        if (retried || wrapper._cancelled) rethrow;
        retried = true;
        await ConvexClient.instance.reconnect();
        await doSubscribe();
        return;
      }
      wrapper._current = handle;
    }

    await doSubscribe();
    return wrapper;
  }

  Future<UserAccount> addLocal({String? name}) async {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final account = UserAccount(id: id, type: AccountType.local, name: name);
    _accounts = [..._accounts, account];
    _activeId = id;
    await _persist();
    notifyListeners();
    return account;
  }

  Future<void> switchTo(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeId = id;
    await _persist();
    final a = activeAccount;
    await _applyConvexAuth(a?.accessToken);
    if (a != null && a.type == AccountType.remote) {
      _scheduleNextRefresh();
    } else {
      _stopRefreshTimer();
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final active = activeAccount;
    _activeId = null;
    _stopRefreshTimer();
    await _persist();
    await _applyConvexAuth(null);
    notifyListeners();
    // Fire-and-forget revoke; never block the UI on the network.
    final refresh = active?.refreshToken;
    if (refresh != null) {
      unawaited(_revokeRefreshToken(refresh));
    }
  }

  Future<void> signOutRemote(String id) async {
    final account = _accounts.firstWhere((a) => a.id == id);
    if (account.type != AccountType.remote) {
      throw StateError('signOutRemote called on non-remote account: $id');
    }
    // TODO: guard against unsynced data once sync is wired up.
    await AppDatabase.deleteForUser(id);
    _accounts = _accounts.where((a) => a.id != id).toList();
    if (_activeId == id) {
      _activeId = null;
      _stopRefreshTimer();
      await _applyConvexAuth(null);
    }
    await _persist();
    notifyListeners();
    final refresh = account.refreshToken;
    if (refresh != null) {
      unawaited(_revokeRefreshToken(refresh));
    }
  }

  Future<void> deleteLocal(String id) async {
    final account = _accounts.firstWhere((a) => a.id == id);
    if (account.type != AccountType.local) {
      throw StateError('deleteLocal called on non-local account: $id');
    }
    await AppDatabase.deleteForUser(id);
    _accounts = _accounts.where((a) => a.id != id).toList();
    if (_activeId == id) _activeId = null;
    await _persist();
    notifyListeners();
  }

  Future<void> mergeLocalIntoRemote(String localId, String remoteId) {
    throw UnimplementedError('Local→remote merge not implemented');
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _http.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static bool _isAuthError(String message) =>
      message.toLowerCase().contains('unauthenticated');

  static String _clientErrorMessage(ClientError e) => switch (e) {
    ClientError_InternalError(:final msg) => msg,
    ClientError_ConvexError(:final data) => data,
    ClientError_ServerError(:final msg) => msg,
  };

  Future<void> _applyConvexAuth(String? token) async {
    try {
      await ConvexClient.instance.setAuth(token: token);
    } catch (e) {
      debugPrint('ConvexClient.setAuth failed: $e');
    }
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _http.post(
      Uri.parse('${AppConfig.convexSiteUrl}$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {}
      throw _AuthHttpError(response.statusCode, decoded, response.body);
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  /// Coalesces concurrent refresh attempts: the proactive timer, the resume
  /// callback, and the on-auth-error retry path can all fire at once.
  Future<bool> _refreshAccessToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final active = activeAccount;
    final refresh = active?.refreshToken;
    if (active == null ||
        active.type != AccountType.remote ||
        refresh == null) {
      return false;
    }
    try {
      final body = await _postJson('/auth/refresh', {'refreshToken': refresh});
      final newAccess = body['accessToken'] as String;
      final newAccessExp = (body['accessTokenExpiresAt'] as num).toInt();

      _replaceAccount(
        active.id,
        (a) => a.copyWith(
          accessToken: newAccess,
          accessTokenExpiresAt: newAccessExp,
          requiresReauth: false,
        ),
      );
      await _applyConvexAuth(newAccess);
      _scheduleNextRefresh();
      return true;
    } on _AuthHttpError catch (e) {
      if (e.statusCode == 401) {
        // Session token revoked. Keep local data — user re-signs in to
        // reconnect; offline mode still works.
        _setRequiresReauth(active.id, true);
        _stopRefreshTimer();
      } else {
        debugPrint('refresh failed: ${e.statusCode} ${e.rawBody}');
      }
      return false;
    } catch (e) {
      debugPrint('refresh request failed: $e');
      return false;
    }
  }

  Future<void> _revokeRefreshToken(String refreshToken) async {
    try {
      await _postJson('/auth/signout', {'refreshToken': refreshToken});
    } catch (e) {
      debugPrint('signout request failed: $e');
    }
  }

  void _scheduleNextRefresh() {
    _stopRefreshTimer();
    final active = activeAccount;
    if (active == null || active.type != AccountType.remote) return;
    final exp = active.accessTokenExpiresAt;
    if (exp == null) return;
    final remainingMs =
        exp -
        DateTime.now().millisecondsSinceEpoch -
        _refreshLeeway.inMilliseconds;
    final delay = remainingMs < 1000
        ? const Duration(seconds: 1)
        : Duration(milliseconds: remainingMs);
    _refreshTimer = Timer(delay, () => unawaited(_refreshAccessToken()));
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _replaceAccount(String id, UserAccount Function(UserAccount) update) {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final current = _accounts[idx];
    final updated = update(current);
    if (identical(updated, current)) return;
    _accounts = [
      ..._accounts.sublist(0, idx),
      updated,
      ..._accounts.sublist(idx + 1),
    ];
    _scheduleSave();
    notifyListeners();
  }

  void _setRequiresReauth(String id, bool value) {
    _replaceAccount(
      id,
      (a) => a.requiresReauth == value ? a : a.copyWith(requiresReauth: value),
    );
  }

  /// Awaitable save. Serialized via [_persistQueue] so concurrent saves can't
  /// interleave their two-key writes. The snapshot is captured at call time so
  /// each queued save writes the state-as-of-its-call, not as-of-execution.
  Future<void> _persist() {
    final encoded = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    final activeSnapshot = _activeId;
    final write = _persistQueue.then((_) async {
      await _storage.write(key: _accountsKey, value: encoded);
      await _storage.write(key: _activeIdKey, value: activeSnapshot);
    });
    _persistQueue = write.catchError((Object e) {
      debugPrint('persist failed: $e');
    });
    return write;
  }

  void _scheduleSave() {
    unawaited(_persist());
  }
}

/// Opaque handle for a Convex subscription that survives JWT refreshes. The
/// underlying [SubscriptionHandle] may be swapped transparently when
/// re-subscribing after an auth failure; callers should never hold onto the
/// inner one.
class ConvexSubscriptionHandle {
  ConvexSubscriptionHandle._();

  bool _cancelled = false;
  SubscriptionHandle? _current;

  void cancel() {
    _cancelled = true;
    _current?.cancel();
    _current = null;
  }
}

/// Thrown by [AuthController._postJson] on non-2xx responses. [body] is the
/// decoded JSON payload if the server returned one, otherwise null.
class _AuthHttpError implements Exception {
  _AuthHttpError(this.statusCode, this.body, this.rawBody);

  final int statusCode;
  final Object? body;
  final String rawBody;

  @override
  String toString() => 'HTTP $statusCode: ${body ?? rawBody}';
}
