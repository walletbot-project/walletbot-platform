import 'dart:convert';

import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:app/database.dart';
// ignore: implementation_imports
import 'package:convex_dart/src/convex_dart_for_generated_code.dart'
    show InternalConvexClient;
import 'package:flutter/foundation.dart';
import 'package:flutter_better_auth/flutter_better_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthController extends ChangeNotifier {
  AuthController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';

  final FlutterSecureStorage _storage;

  List<UserAccount> _accounts = const [];
  String? _activeId;

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
    debugPrint(
      'load: activeId=$_activeId convexJwt=${a?.convexJwt == null ? "null" : "<${a!.convexJwt!.length} chars>"} requiresReauth=${a?.requiresReauth}',
    );
    _applyBearerToken(a?.token);
    await _applyConvexAuth(a?.convexJwt);
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

  Future<void> _applyConvexAuth(String? token) async {
    try {
      debugPrint(
        'ConvexClient.setAuth(${token == null ? "null" : "<jwt ${token.length} chars>"})',
      );
      await InternalConvexClient.instance.setAuth(token: token);
      debugPrint('ConvexClient.setAuth OK');
    } catch (e) {
      debugPrint('ConvexClient.setAuth failed: $e');
    }
  }

  Future<String?> _fetchConvexJwt() async {
    try {
      final res = await FlutterBetterAuth.dioClient.get(
        '${AppConfig.betterAuthBaseUrl}/convex/token',
      );
      debugPrint('fetchConvexJwt status=${res.statusCode} body=${res.data}');
      final data = res.data;
      if (data is Map && data['token'] is String) {
        return data['token'] as String;
      }
      debugPrint('fetchConvexJwt: unexpected shape — returning null');
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
    try {
      return await _signInWithGoogle();
    } catch (e, s) {
      debugPrint('signInWithGoogle FAILED: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }

  Future<UserAccount> _signInWithGoogle() async {
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
      debugPrint('sign-in error [${err?.code}]: ${err?.message}');
      debugPrint('sign-in stack: ${err?.stack}');
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
      debugPrint(
        'refreshActiveSession: status=${res.statusCode} body=${res.data}',
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
    notifyListeners();
  }

  Future<void> signOut() async {
    _activeId = null;
    await _persist();
    _applyBearerToken(null);
    await _applyConvexAuth(null);
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
