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

/// Owns the device's account list and the active Convex auth session.
///
/// Auth refresh is delegated entirely to `convex_flutter`'s `setAuthWithRefresh`
/// — we register a token-fetcher and the Rust client calls it on schedule
/// (60s before JWT expiry) and on every WebSocket reconnect. Our only job is
/// to mint a fresh access JWT on demand by POSTing the long-lived session
/// token to `/auth/refresh`.
///
/// Offline-first: we never delete local accounts on validation failure. If
/// the session is revoked server-side, we flip [UserAccount.requiresReauth]
/// so the UI can prompt; the account stays on disk.
class AuthController extends ChangeNotifier {
  AuthController({http.Client? httpClient, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _http = httpClient ?? http.Client();

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';

  final FlutterSecureStorage _storage;
  final http.Client _http;

  List<UserAccount> _accounts = const [];
  String? _activeId;
  AuthHandleWrapper? _authHandle;
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
    await _attachAuthForActive();
    notifyListeners();
  }

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
      // Wire format kept as `refreshToken` for backward compat with the
      // backend response.
      sessionToken: body['refreshToken'] as String,
    );

    _accounts = [
      for (final a in _accounts)
        if (a.id != account.id) a,
      account,
    ];
    _activeId = account.id;
    await _persist();
    await _attachAuthForActive();
    notifyListeners();
    return account;
  }

  Future<UserAccount> addLocal({String? name}) async {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final account = UserAccount(id: id, type: AccountType.local, name: name);
    _accounts = [..._accounts, account];
    _activeId = id;
    await _persist();
    await _attachAuthForActive();
    notifyListeners();
    return account;
  }

  Future<void> switchTo(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeId = id;
    await _persist();
    await _attachAuthForActive();
    notifyListeners();
  }

  Future<void> signOut() async {
    final active = activeAccount;
    _activeId = null;
    await _detachAuth();
    await _persist();
    notifyListeners();
    final session = active?.sessionToken;
    if (session != null) {
      // Fire-and-forget revoke; never block the UI on the network.
      unawaited(_revokeSessionToken(session));
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
      await _detachAuth();
    }
    await _persist();
    notifyListeners();
    final session = account.sessionToken;
    if (session != null) {
      unawaited(_revokeSessionToken(session));
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
    unawaited(_detachAuth());
    _http.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _attachAuthForActive() async {
    await _detachAuth();
    final active = activeAccount;
    if (active == null ||
        active.type != AccountType.remote ||
        active.sessionToken == null) {
      return;
    }
    _authHandle = await ConvexClient.instance.setAuthWithRefresh(
      // Called immediately, on schedule (~60 s before JWT expiry), and on
      // every WebSocket reconnect. Must always return a *fresh* JWT.
      fetchToken: _fetchFreshAccessToken,
      onAuthChange: (isAuthenticated) {
        // Cleared by the Rust client when the fetcher returns null —
        // typically because the session token was revoked server-side.
        if (!isAuthenticated) {
          _setRequiresReauth(active.id, true);
        }
      },
    );
  }

  Future<void> _detachAuth() async {
    final handle = _authHandle;
    _authHandle = null;
    if (handle != null) {
      handle.dispose();
    }
    await ConvexClient.instance.setAuth(token: null);
  }

  /// Token fetcher passed to `setAuthWithRefresh`. Returns a fresh access JWT
  /// minted from the active account's session token, or `null` if the session
  /// is revoked / no remote account is active. Returning `null` causes the
  /// Rust client to clear auth and surface it via [onAuthChange].
  Future<String?> _fetchFreshAccessToken() async {
    final active = activeAccount;
    final session = active?.sessionToken;
    if (active == null ||
        active.type != AccountType.remote ||
        session == null) {
      return null;
    }
    try {
      final body = await _postJson('/auth/refresh', {'refreshToken': session});
      _setRequiresReauth(active.id, false);
      return body['accessToken'] as String;
    } on _AuthHttpError catch (e) {
      // 401 means the session token is revoked or expired. Surface to the
      // UI; keep the account on disk (offline mode).
      if (e.statusCode == 401) {
        _setRequiresReauth(active.id, true);
        return null;
      }
      debugPrint('refresh failed: ${e.statusCode} ${e.rawBody}');
      // Transient (5xx, network). Return null so the Rust client can retry
      // later; don't flip requiresReauth on a server hiccup.
      return null;
    } catch (e) {
      debugPrint('refresh request failed: $e');
      return null;
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

  Future<void> _revokeSessionToken(String sessionToken) async {
    try {
      await _postJson('/auth/signout', {'refreshToken': sessionToken});
    } catch (e) {
      debugPrint('signout request failed: $e');
    }
  }

  void _setRequiresReauth(String id, bool value) {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final current = _accounts[idx];
    if (current.requiresReauth == value) return;
    _accounts = [
      ..._accounts.sublist(0, idx),
      current.copyWith(requiresReauth: value),
      ..._accounts.sublist(idx + 1),
    ];
    unawaited(_persist());
    notifyListeners();
  }

  /// Awaitable save. Serialized via [_persistQueue] so concurrent saves can't
  /// interleave their two-key writes.
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
}

class _AuthHttpError implements Exception {
  _AuthHttpError(this.statusCode, this.body, this.rawBody);

  final int statusCode;
  final Object? body;
  final String rawBody;

  @override
  String toString() => 'HTTP $statusCode: ${body ?? rawBody}';
}
