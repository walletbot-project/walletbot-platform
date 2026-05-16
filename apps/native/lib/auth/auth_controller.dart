import 'dart:async';
import 'dart:convert';

import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
import 'package:convex_dart/convex_dart.dart' show ConvexClientError;
// ignore: implementation_imports
import 'package:convex_dart/src/convex_dart_for_generated_code.dart'
    show InternalConvexClient;
// ignore: implementation_imports
import 'package:convex_dart/src/rust/base_client/query_result.dart'
    show FunctionResult, FunctionResult_ErrorMessage, FunctionResult_Value;
// ignore: implementation_imports
import 'package:convex_dart/src/rust/dart.dart' show SubscriptionHandle;
// ignore: implementation_imports
import 'package:convex_dart/src/rust/lib.dart' show BTreeMapStringValue;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class AuthController extends ChangeNotifier {
  AuthController({http.Client? httpClient, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _http = _AuthHttpClient(
      inner: httpClient ?? http.Client(),
      onRotatedToken: _handleRotatedBearerToken,
    );
  }

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';
  // JWT lifetime is 15 minutes; refresh comfortably before that.
  static const _convexJwtRefreshInterval = Duration(minutes: 13);

  final FlutterSecureStorage _storage;
  late final _AuthHttpClient _http;

  List<UserAccount> _accounts = const [];
  String? _activeId;
  Timer? _convexJwtTimer;
  Future<void>? _convexJwtRefreshInFlight;
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
    _applyBearerToken(a?.token);
    await _applyConvexAuth(a?.convexJwt);
    if (a != null && a.type == AccountType.remote) {
      _startConvexJwtTimer();
    }
    notifyListeners();
  }

  // Sets/clears the Authorization header used by the better-auth bearer plugin.
  // Mobile uses bearer instead of cookies because cookie persistence is unreliable.
  void _applyBearerToken(String? token) {
    if (token == null || token.isEmpty) {
      _http.headers.remove('Authorization');
    } else {
      _http.headers['Authorization'] = 'Bearer $token';
    }
  }

  void _handleRotatedBearerToken(String newToken) {
    final active = activeAccount;
    if (active == null || active.token == newToken) return;
    _applyBearerToken(newToken);
    _replaceAccount(active.id, (a) => a.copyWith(token: newToken));
  }

  /// Replaces an account in [_accounts] by id and schedules a save. No-op if
  /// the id is unknown or [update] returns an equal value. Notifies listeners
  /// only when state actually changed.
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

  /// True iff [message] looks like a Convex unauthenticated error. convex_dart
  /// has no typed auth-error variant, so we sniff the string. If the upstream
  /// wording ever changes, the auth-retry plumbing in [runConvexAuthenticated]
  /// and [subscribeConvex] silently stops triggering — keep all sniffing here.
  static bool _isAuthError(String message) =>
      message.toLowerCase().contains('unauthenticated');

  void _startConvexJwtTimer() {
    _convexJwtTimer?.cancel();
    _convexJwtTimer = Timer.periodic(_convexJwtRefreshInterval, (_) {
      unawaited(_refreshConvexJwtOnly());
    });
  }

  void _stopConvexJwtTimer() {
    _convexJwtTimer?.cancel();
    _convexJwtTimer = null;
  }

  // Mint a fresh Convex JWT without round-tripping /get-session. Used by the
  // periodic timer; keeps old JWT in place if the call fails (offline-first).
  //
  // Coalesces concurrent callers: the 13-min timer and runConvexAuthenticated's
  // retry path can fire simultaneously — without this, two refreshes race and
  // the older JWT could land last via setAuth.
  Future<void> _refreshConvexJwtOnly() {
    final existing = _convexJwtRefreshInFlight;
    if (existing != null) return existing;
    final future = _doRefreshConvexJwt();
    _convexJwtRefreshInFlight = future;
    return future.whenComplete(() => _convexJwtRefreshInFlight = null);
  }

  Future<void> _doRefreshConvexJwt() async {
    final active = activeAccount;
    if (active == null || active.type != AccountType.remote) return;
    final jwt = await _fetchConvexJwt();
    if (jwt == null) return;
    await _applyConvexAuth(jwt);
    _setConvexJwt(active.id, jwt);
  }

  /// Wraps a Convex call so that if the backend reports an authentication
  /// failure, we mint a fresh JWT and retry once. Use this for any Convex
  /// query/mutation/action that requires the signed-in user.
  Future<T> runConvexAuthenticated<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ConvexClientError catch (e) {
      if (!_isAuthError(e.message)) rethrow;
      await _refreshConvexJwtOnly();
      return await fn();
    }
  }

  /// Subscribes to a Convex query and keeps the subscription alive across
  /// JWT refreshes. If the backend reports an authentication failure, we
  /// transparently mint a fresh JWT and re-subscribe under the same handle.
  ///
  /// Caller owns the returned handle and MUST call [ConvexSubscriptionHandle.cancel]
  /// when no longer needed (typically in widget `dispose`).
  Future<ConvexSubscriptionHandle> subscribeConvex({
    required String name,
    required BTreeMapStringValue args,
    required FutureOr<void> Function(FunctionResult) onUpdate,
  }) async {
    final wrapper = ConvexSubscriptionHandle._();
    var authRetries = 0;
    const maxAuthRetries = 3;

    Future<void> doSubscribe() async {
      if (wrapper._cancelled) return;
      late SubscriptionHandle handle;
      handle = await InternalConvexClient.instance.subscribe(
        name: name,
        args: args,
        onUpdate: (result) async {
          // Drop stale callbacks from a handle that's been replaced or cancelled.
          if (wrapper._cancelled || wrapper._current != handle) return;

          if (result is FunctionResult_ErrorMessage &&
              _isAuthError(result.field0)) {
            if (authRetries >= maxAuthRetries) {
              debugPrint(
                'subscribeConvex($name): giving up after $maxAuthRetries auth retries',
              );
              return;
            }
            authRetries++;
            handle.cancel();
            wrapper._current = null;
            await _refreshConvexJwtOnly();
            await doSubscribe();
            return;
          }

          if (result is FunctionResult_Value) authRetries = 0;
          await onUpdate(result);
        },
      );
      wrapper._current = handle;
    }

    await doSubscribe();
    return wrapper;
  }

  @override
  void dispose() {
    _stopConvexJwtTimer();
    _http.close();
    super.dispose();
  }

  Future<void> _applyConvexAuth(String? token) async {
    try {
      await InternalConvexClient.instance.setAuth(token: token);
    } catch (e) {
      debugPrint('ConvexClient.setAuth failed: $e');
    }
  }

  Future<String?> _fetchConvexJwt() async {
    try {
      final data = await _http.jsonGet('/convex/token');
      if (data is Map && data['token'] is String) {
        return data['token'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('fetchConvexJwt failed: $e');
      return null;
    }
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

  Future<UserAccount> signInWithGoogle() async {
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in returned no idToken');
    }

    final Object? signInData;
    try {
      signInData = await _http.jsonPost(
        '/sign-in/social',
        body: {
          'provider': 'google',
          'idToken': {'token': idToken},
        },
      );
    } on HttpError catch (e) {
      final body = e.body;
      if (body is Map) {
        throw StateError(
          'Better-auth sign-in failed [${body['code']}]: ${body['message']}',
        );
      }
      throw StateError('Better-auth sign-in failed: HTTP ${e.statusCode}');
    }
    final sessionToken = (signInData is Map ? signInData['token'] : null);
    if (sessionToken is! String) {
      throw StateError('Sign-in response missing token');
    }
    _applyBearerToken(sessionToken);

    // The Convex better-auth adapter returns numeric ms-epoch timestamps for
    // session fields, so we read /get-session as raw JSON instead of through
    // a typed client that would try to parse them as ISO strings.
    final data = await _http.jsonGet('/get-session') as Map<String, Object?>?;
    if (data == null) {
      throw StateError('Empty session response');
    }
    final userJson = data['user'] as Map<String, Object?>?;
    if (userJson == null) {
      throw StateError('Session response had no user');
    }

    final convexJwt = await _fetchConvexJwt();
    await _applyConvexAuth(convexJwt);

    final account = UserAccount(
      id: userJson['id'] as String,
      type: AccountType.remote,
      name: userJson['name'] as String?,
      email: userJson['email'] as String?,
      token: sessionToken,
      convexJwt: convexJwt,
      picture: userJson['image'] as String?,
    );

    _accounts = [
      for (final a in _accounts)
        if (a.id != account.id) a,
      account,
    ];
    _activeId = account.id;
    await _persist();
    _startConvexJwtTimer();
    notifyListeners();
    return account;
  }

  /// Opportunistically validate the active remote session against the backend.
  /// Never deletes local data. On 401 or network failure, marks the account
  /// as needing re-auth so the UI can prompt — the user is never locked out.
  Future<void> refreshActiveSession() async {
    final active = activeAccount;
    if (active == null || active.type != AccountType.remote) return;
    try {
      final data = await _http.jsonGet('/get-session');
      final ok = data is Map && data['user'] != null;
      _setRequiresReauth(active.id, !ok);
      if (ok) {
        final jwt = await _fetchConvexJwt();
        if (jwt != null) {
          await _applyConvexAuth(jwt);
          _setConvexJwt(active.id, jwt);
        }
      }
    } catch (e) {
      debugPrint('refreshActiveSession failed: $e');
      _setRequiresReauth(active.id, true);
    }
  }

  void _setConvexJwt(String id, String jwt) {
    _replaceAccount(
      id,
      (a) => a.convexJwt == jwt ? a : a.copyWith(convexJwt: jwt),
    );
  }

  void _setRequiresReauth(String id, bool value) {
    _replaceAccount(
      id,
      (a) => a.requiresReauth == value ? a : a.copyWith(requiresReauth: value),
    );
  }

  Future<void> switchTo(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeId = id;
    await _persist();
    final a = activeAccount;
    _applyBearerToken(a?.token);
    await _applyConvexAuth(a?.convexJwt);
    if (a != null && a.type == AccountType.remote) {
      _startConvexJwtTimer();
    } else {
      _stopConvexJwtTimer();
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _activeId = null;
    await _persist();
    _applyBearerToken(null);
    await _applyConvexAuth(null);
    _stopConvexJwtTimer();
    notifyListeners();
  }

  Future<void> signOutRemote(String id) async {
    final account = _accounts.firstWhere((a) => a.id == id);
    if (account.type != AccountType.remote) {
      throw StateError('signOutRemote called on non-remote account: $id');
    }
    // TODO: guard against unsynced data once sync is wired up.
    await AppDatabase.deleteForUser(id);
    _accounts = _accounts.where((a) => a.id != id).toList();
    if (_activeId == id) _activeId = null;
    await _persist();
    notifyListeners();
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

  /// Fire-and-forget variant for reactive updates from background paths
  /// (token rotation, JWT refresh). Goes through the same queue, so it can
  /// never overlap with an awaitable [_persist].
  void _scheduleSave() {
    unawaited(_persist());
  }
}

/// Opaque handle for a Convex subscription that survives JWT refreshes. The
/// underlying convex_dart [SubscriptionHandle] may be swapped transparently
/// when re-subscribing after an auth failure; callers should never hold onto
/// the inner one.
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

/// Thrown by [_AuthHttpClient.jsonGet] / [_AuthHttpClient.jsonPost] on non-2xx
/// responses. [body] is the decoded JSON payload if the server returned one
/// (e.g. better-auth's `{code, message}` shape), otherwise null.
class HttpError implements Exception {
  HttpError(this.statusCode, this.body);

  final int statusCode;
  final Object? body;

  @override
  String toString() => 'HTTP $statusCode: ${body ?? '(empty body)'}';
}

/// http.Client that injects default headers (Origin, Authorization) on every
/// request and inspects responses for better-auth's rotated `set-auth-token`
/// header so the controller can capture the new session token.
class _AuthHttpClient extends http.BaseClient {
  _AuthHttpClient({required http.Client inner, required this.onRotatedToken})
    : _inner = inner;

  final http.Client _inner;
  final void Function(String) onRotatedToken;

  // Better-auth's origin-check middleware reads the standard `Origin` header.
  // `flutter://` must match a trustedOrigins entry on the server.
  final Map<String, String> headers = {'Origin': 'flutter://'};

  Uri _url(String path) => Uri.parse('${AppConfig.betterAuthBaseUrl}$path');

  /// GETs [path] (resolved against the better-auth base URL) and returns the
  /// decoded JSON body. Throws [HttpError] on non-2xx.
  Future<Object?> jsonGet(String path) async {
    final res = await get(_url(path));
    return _decodeOrThrow(res);
  }

  /// POSTs JSON-encoded [body] to [path] (resolved against the better-auth
  /// base URL) and returns the decoded JSON response body. Throws [HttpError]
  /// on non-2xx.
  Future<Object?> jsonPost(String path, {Map<String, Object?>? body}) async {
    final res = await post(
      _url(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body ?? const {}),
    );
    return _decodeOrThrow(res);
  }

  Object? _decodeOrThrow(http.Response res) {
    final decoded = _tryDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpError(res.statusCode, decoded);
    }
    return decoded;
  }

  static Object? _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    headers.forEach((k, v) => request.headers.putIfAbsent(k, () => v));
    final response = await _inner.send(request);
    // Bearer plugin issues a rotated session token via this header when
    // better-auth's `updateAge` threshold is crossed. Capture it so we
    // don't keep replaying a token that's about to expire.
    final rotated = response.headers['set-auth-token'];
    if (rotated != null && rotated.isNotEmpty) {
      onRotatedToken(rotated);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
