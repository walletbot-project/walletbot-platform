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
/// Auth refresh is delegated to `convex_flutter`'s `setAuthWithRefresh`.
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
  bool _convexAuthenticated = false;
  Future<void> _persistQueue = Future.value();

  List<UserAccount> get accounts => List.unmodifiable(_accounts);
  String? get activeId => _activeId;
  bool get convexAuthenticated => _convexAuthenticated;
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
      fetchToken: _fetchFreshAccessToken,
      onAuthChange: (isAuthenticated) {
        if (_convexAuthenticated == isAuthenticated) return;
        _convexAuthenticated = isAuthenticated;
        notifyListeners();
      },
    );
  }

  Future<void> _detachAuth() async {
    final handle = _authHandle;
    _authHandle = null;
    if (handle != null) {
      handle.dispose();
    }
    if (_convexAuthenticated) {
      _convexAuthenticated = false;
      notifyListeners();
    }
    await ConvexClient.instance.setAuth(token: null);
  }

  Future<String?> _fetchFreshAccessToken() async {
    debugPrint('auth: fetching fresh access token');
    final active = activeAccount;
    final session = active?.sessionToken;
    if (active == null || session == null) return null;
    try {
      debugPrint('auth: refreshing access token');
      final body = await _postJson('/auth/refresh', {'refreshToken': session});
      return body['accessToken'] as String;
    } catch (e) {
      debugPrint('auth: token refresh failed: $e');
      if (e is _AuthHttpError && e.statusCode == 401) {
        await _markRequiresReauth(active.id);
      }
      rethrow;
    }
  }

  Future<void> _markRequiresReauth(String accountId) async {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx == -1 || _accounts[idx].requiresReauth) return;
    final updated = [..._accounts];
    updated[idx] = updated[idx].copyWith(requiresReauth: true);
    _accounts = updated;
    await _persist();
    notifyListeners();
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
