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

  Future<UserAccount> signInWithGoogle({bool rejectExisting = false}) async {
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in returned no idToken');
    }

    final body = await _postJson('/auth/google', {'idToken': idToken});
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
    );
  }

  Future<UserAccount> signInWithEmail({
    required String email,
    required String password,
    bool rejectExisting = false,
  }) async {
    final body = await _postJson('/auth/email/sign-in', {
      'email': email,
      'password': password,
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
    );
  }

  /// Under server-side email verification this always throws
  /// [EmailNotVerifiedException] on successful account creation (the backend
  /// sends the verification email and returns no session). The caller must
  /// route to the verification-pending state.
  Future<UserAccount> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    bool rejectExisting = false,
  }) async {
    final body = await _postJson('/auth/email/sign-up', {
      'name': name,
      'email': email,
      'password': password,
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
    );
  }

  /// Requests a password-reset email. Enumeration-safe: unknown emails still
  /// return 200. Throws [AuthHttpError] when the server failed to send the
  /// email (`email_send_failed`), or on network failure.
  Future<void> requestPasswordReset({required String email}) async {
    await _postJson('/auth/password/forgot', {'email': email});
  }

  /// Re-sends the verification email. Enumeration-safe like
  /// [requestPasswordReset], and throws on the same failures.
  Future<void> resendVerificationEmail({required String email}) async {
    await _postJson('/auth/email/resend-verification', {'email': email});
  }

  Future<UserAccount> addLocal({required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Local accounts require a name');
    }

    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final account = UserAccount(
      id: id,
      type: AccountType.local,
      name: trimmedName,
    );
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

  Future<UserAccount> _saveRemoteAccountFromAuthResponse(
    Map<String, Object?> body, {
    bool rejectExisting = false,
  }) async {
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

    // When the user is explicitly adding an account (vs. re-authenticating an
    // existing one), signing into an account already on the device is a no-op
    // that would silently switch to it. Surface it as an error instead.
    if (rejectExisting && _accounts.any((a) => a.id == account.id)) {
      throw AccountAlreadyAddedError(account.email);
    }

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
      if (e is AuthHttpError && e.statusCode == 401) {
        await _markRequiresReauth(active.id);
      }
      rethrow;
    }
  }

  Future<String?> fetchAccessTokenForHttp() => _fetchFreshAccessToken();

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
      // Keep the forensic trail: the UI deliberately shows generic messages,
      // so this log line is the only evidence of what the server said. Never
      // log the request body — it may contain a password.
      debugPrint(
        'auth: POST $path failed: HTTP ${response.statusCode} '
        'body=${response.body}',
      );
      if (decoded is Map<String, Object?> &&
          decoded['code'] == 'email_not_verified') {
        throw EmailNotVerifiedException(
          response.statusCode,
          decoded,
          response.body,
        );
      }
      if (decoded is Map<String, Object?> &&
          decoded['code'] == 'account_exists') {
        throw AccountExistsException(
          response.statusCode,
          decoded,
          response.body,
        );
      }
      throw AuthHttpError(response.statusCode, decoded, response.body);
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

/// Thrown when the user tries to add an account that is already on the device.
class AccountAlreadyAddedError implements Exception {
  AccountAlreadyAddedError(this.email);

  final String? email;

  @override
  String toString() => 'Account already added: ${email ?? '(unknown email)'}';
}

/// Non-2xx response from the auth backend. [code] is the flat `{ code }`
/// field of the JSON error body when present.
class AuthHttpError implements Exception {
  AuthHttpError(this.statusCode, this.body, this.rawBody);

  final int statusCode;
  final Object? body;
  final String rawBody;

  String? get code {
    final b = body;
    return b is Map<String, Object?> ? b['code'] as String? : null;
  }

  @override
  String toString() => 'HTTP $statusCode: ${body ?? rawBody}';
}

/// The account exists but its email is unverified (`email_not_verified`).
/// Thrown by sign-in AND sign-up under server-side email verification; the
/// backend (re-)sends the verification email on the attempt that triggers
/// this.
class EmailNotVerifiedException extends AuthHttpError {
  EmailNotVerifiedException(super.statusCode, super.body, super.rawBody);
}

/// Sign-up hit an address that is already registered (`account_exists`).
/// The backend intentionally doesn't say which provider that account uses —
/// it may have both a password and a social login — so the UI points at
/// either without narrowing it down.
class AccountExistsException extends AuthHttpError {
  AccountExistsException(super.statusCode, super.body, super.rawBody);
}
