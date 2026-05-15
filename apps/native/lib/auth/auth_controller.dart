import 'dart:async';
import 'dart:convert';

import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
import 'package:convex_dart/convex_dart.dart' show ConvexClientError;
// ignore: implementation_imports
import 'package:convex_dart/src/convex_dart_for_generated_code.dart'
    show InternalConvexClient;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_better_auth/flutter_better_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthController extends ChangeNotifier {
  AuthController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _attachDioInterceptors();
  }

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';
  // JWT lifetime is 15 minutes; refresh comfortably before that.
  static const _convexJwtRefreshInterval = Duration(minutes: 13);

  final FlutterSecureStorage _storage;

  List<UserAccount> _accounts = const [];
  String? _activeId;
  Timer? _convexJwtTimer;

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

  // Sets/clears the Authorization header used by the better-auth bearer plugin
  // on the shared dio client. Mobile uses bearer instead of cookies because
  // cookie_jar persistence is unreliable.
  void _applyBearerToken(String? token) {
    if (token == null || token.isEmpty) {
      FlutterBetterAuth.dioClient.options.headers.remove('Authorization');
    } else {
      FlutterBetterAuth.dioClient.options.headers['Authorization'] =
          'Bearer $token';
    }
  }

  void _attachDioInterceptors() {
    FlutterBetterAuth.dioClient.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          // Bearer plugin issues a rotated session token via this header when
          // better-auth's `updateAge` threshold is crossed. Capture it so we
          // don't keep replaying a token that's about to expire.
          final rotated = response.headers.value('set-auth-token');
          if (rotated != null && rotated.isNotEmpty) {
            _handleRotatedBearerToken(rotated);
          }
          handler.next(response);
        },
      ),
    );
  }

  void _handleRotatedBearerToken(String newToken) {
    final active = activeAccount;
    if (active == null || active.token == newToken) return;
    _applyBearerToken(newToken);
    final idx = _accounts.indexWhere((a) => a.id == active.id);
    if (idx < 0) return;
    _accounts = [
      ..._accounts.sublist(0, idx),
      _accounts[idx].copyWith(token: newToken),
      ..._accounts.sublist(idx + 1),
    ];
    _persist();
    notifyListeners();
  }

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
  Future<void> _refreshConvexJwtOnly() async {
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
  ///
  /// Note: brittle. convex_dart surfaces auth failures as a generic
  /// ConvexClientError with a string message — we sniff for "unauthenticated"
  /// since the library has no typed auth-error variant. If the library ever
  /// changes that wording the retry will silently stop triggering.
  Future<T> runConvexAuthenticated<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ConvexClientError catch (e) {
      if (!e.message.toLowerCase().contains('unauthenticated')) rethrow;
      await _refreshConvexJwtOnly();
      return await fn();
    }
  }

  @override
  void dispose() {
    _stopConvexJwtTimer();
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
      final res = await FlutterBetterAuth.dioClient.get(
        '${AppConfig.betterAuthBaseUrl}/convex/token',
      );
      final data = res.data;
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

    final signInResult = await FlutterBetterAuth.client.signIn.social(
      provider: 'google',
      idToken: SocialIdTokenBody(token: idToken),
    );
    final signInData = signInResult.data;
    if (signInData == null) {
      final err = signInResult.error;
      throw StateError(
        'Better-auth sign-in failed [${err?.code}]: ${err?.message}',
      );
    }
    _applyBearerToken(signInData.token);

    // Bypass flutter_better_auth's getSession() because the Convex adapter
    // returns numeric ms-epoch timestamps and the freezed Session model
    // hard-casts those fields to String for DateTime.parse, blowing up.
    final raw = await FlutterBetterAuth.dioClient.get(
      '${AppConfig.betterAuthBaseUrl}/get-session',
    );
    final data = raw.data as Map<String, Object?>?;
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
      token: signInData.token,
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
      final res = await FlutterBetterAuth.dioClient.get(
        '${AppConfig.betterAuthBaseUrl}/get-session',
      );
      final data = res.data;
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
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    if (_accounts[idx].convexJwt == jwt) return;
    _accounts = [
      ..._accounts.sublist(0, idx),
      _accounts[idx].copyWith(convexJwt: jwt),
      ..._accounts.sublist(idx + 1),
    ];
    _persist();
    notifyListeners();
  }

  void _setRequiresReauth(String id, bool value) {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    if (_accounts[idx].requiresReauth == value) return;
    _accounts = [
      ..._accounts.sublist(0, idx),
      _accounts[idx].copyWith(requiresReauth: value),
      ..._accounts.sublist(idx + 1),
    ];
    _persist();
    notifyListeners();
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

  Future<void> _persist() async {
    final encoded = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _accountsKey, value: encoded);
    await _storage.write(key: _activeIdKey, value: _activeId);
  }
}
