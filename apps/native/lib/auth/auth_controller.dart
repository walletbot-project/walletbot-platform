import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app/auth/account.dart';
import 'package:app/config.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/database.dart';
import 'package:app/legal/legal_acceptance_payload.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

/// A request to turn the local account [accountId] into an online one, handed
/// to the sign-in/sign-up calls of [AuthController].
class LocalPromotion {
  const LocalPromotion({required this.accountId, required this.beforeConvert});

  /// [UserAccount.id] of the local account being promoted.
  final String accountId;

  /// Runs once the server has accepted the promotion and before the account
  /// is converted, while the account's database is still open: it flags the
  /// account's rows for the first push. Throwing aborts the conversion; the
  /// server side is idempotent, so the user can simply retry.
  final Future<void> Function() beforeConvert;
}

/// Owns the device's account list and the active Convex auth session.
/// Token refresh scheduling is delegated to [ConvexClient.setAuth].
class AuthController extends ChangeNotifier {
  AuthController({
    ConvexClient? convex,
    http.Client? httpClient,
    FlutterSecureStorage? storage,
    String Function()? localeTag,
    Future<void> Function()? awaitFrame,
  }) : _convex = convex,
       _awaitFrame = awaitFrame ?? (() => WidgetsBinding.instance.endOfFrame),
       _storage = storage ?? const FlutterSecureStorage(),
       _http = httpClient ?? http.Client(),
       _localeTag = localeTag {
    _authStateSub = convex?.authState.listen((state) {
      final authenticated = state == AuthState.authenticated;
      if (_convexAuthenticated == authenticated) return;
      _convexAuthenticated = authenticated;
      notifyListeners();
    });
  }

  static const _accountsKey = 'accounts';
  static const _activeIdKey = 'active_account_id';

  /// Null only in tests that never exercise the Convex session (production
  /// always wires one): auth attach/detach become no-ops without it.
  final ConvexClient? _convex;
  final FlutterSecureStorage _storage;
  final http.Client _http;

  /// The device's effective language tag, sent as `Accept-Language` on every
  /// auth request. The backend needs it for the emails these endpoints trigger
  /// (verification, password reset): a brand-new account has no stored
  /// language yet, and native reaches better-auth through direct `auth.api.*`
  /// calls that carry no request of their own. Null (tests, and any caller
  /// that doesn't wire it) simply omits the header, and the server falls back
  /// to its default locale.
  final String Function()? _localeTag;

  /// Resolves once the frame in progress has been built. Promotion needs it to
  /// let the account's UI subtree (and the database connection it owns) go
  /// away before the same database is reopened as a remote account. Injected
  /// so tests need not pump frames.
  final Future<void> Function() _awaitFrame;

  List<UserAccount> _accounts = const [];
  String? _activeId;
  StreamSubscription<AuthState>? _authStateSub;
  bool _convexAuthenticated = false;
  Future<void> _persistQueue = Future.value();
  String? _promotingId;

  List<UserAccount> get accounts => List.unmodifiable(_accounts);
  String? get activeId => _activeId;

  /// The local account being converted to an online one right now, if any.
  /// While set, the app shows a bare placeholder instead of that account's
  /// subtree so its database connection is closed before it is reopened.
  String? get promotingId => _promotingId;
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
    // Assign once, persist offline, and send only when the account uses AI.
    if (_accounts.any(
      (a) => a.type == AccountType.local && a.localAccountId == null,
    )) {
      _accounts = [
        for (final a in _accounts)
          if (a.type == AccountType.local && a.localAccountId == null)
            a.copyWith(localAccountId: const Uuid().v4())
          else
            a,
      ];
      // Preserve the active selection while persisting the migration.
      _activeId = await _storage.read(key: _activeIdKey);
      await _persist();
    }
    _activeId = await _storage.read(key: _activeIdKey);
    await _attachAuthForActive();
    notifyListeners();
  }

  Future<UserAccount> signInWithGoogle({
    bool rejectExisting = false,
    LocalPromotion? promotion,
  }) async {
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in returned no idToken');
    }

    final body = await _postJson('/auth/google', {
      'idToken': idToken,
      ..._promotionFields(promotion),
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
      promotion: promotion,
    );
  }

  /// Sign in with Apple. iOS only — the login screen shows the button nowhere
  /// else, and this would need `webAuthenticationOptions` (a Services ID and a
  /// browser round trip) to work on Android.
  ///
  /// The nonce is generated here and travels two ways: Apple gets its SHA-256
  /// digest and embeds that in `identityToken`, while the backend gets the raw
  /// value and re-hashes it to compare. Sending the digest to both would hash
  /// it twice and the token would fail verification.
  ///
  /// `givenName`/`familyName` are only ever populated on the user's FIRST
  /// authorization of this app; every later sign-in returns them null and the
  /// name already stored on the account stands.
  Future<UserAccount> signInWithApple({
    bool rejectExisting = false,
    LocalPromotion? promotion,
  }) async {
    final rawNonce = _generateNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple sign-in returned no identityToken');
    }

    final body = await _postJson('/auth/apple', {
      'idToken': idToken,
      'nonce': rawNonce,
      if (credential.givenName != null) 'givenName': credential.givenName,
      if (credential.familyName != null) 'familyName': credential.familyName,
      ..._promotionFields(promotion),
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
      promotion: promotion,
    );
  }

  Future<UserAccount> signInWithEmail({
    required String email,
    required String password,
    bool rejectExisting = false,
    LocalPromotion? promotion,
  }) async {
    final body = await _postJson('/auth/email/sign-in', {
      'email': email,
      'password': password,
      ..._promotionFields(promotion),
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
      promotion: promotion,
    );
  }

  /// Under server-side email verification this always throws
  /// [EmailNotVerifiedException] on successful account creation (the backend
  /// sends the verification email and returns no session). The caller must
  /// route to the verification-pending state.
  ///
  /// [acceptance] carries the sign-up form's Terms/Privacy consent. It is
  /// recorded against the created user by the endpoint, which is the only
  /// moment those checkboxes can be tied to an account: this call issues no
  /// session, so nothing afterwards could authenticate the write.
  Future<UserAccount> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    LegalAcceptancePayload? acceptance,
    bool rejectExisting = false,
    LocalPromotion? promotion,
  }) async {
    final body = await _postJson('/auth/email/sign-up', {
      'name': name,
      'email': email,
      'password': password,
      if (acceptance != null) 'acceptance': acceptance.toJson(),
      ..._promotionFields(promotion),
    });
    return _saveRemoteAccountFromAuthResponse(
      body,
      rejectExisting: rejectExisting,
      promotion: promotion,
    );
  }

  /// Requests a password-reset email. Returning normally means an email was
  /// really handed to Resend — every other outcome throws [AuthHttpError] with
  /// a `code` the caller renders: `account_not_found` (no account for that
  /// address), `rate_limited`, `email_send_failed`. These used to answer 200
  /// as well, to keep the endpoint enumeration-safe, which meant the UI
  /// promised mail that never went out.
  Future<void> requestPasswordReset({required String email}) async {
    await _postJson('/auth/password/forgot', {'email': email});
  }

  /// Re-sends the verification email. Same contract as
  /// [requestPasswordReset], plus `email_already_verified` — there is nothing
  /// to re-send for an address that is verified (every Google-registered one).
  Future<void> resendVerificationEmail({required String email}) async {
    await _postJson('/auth/email/resend-verification', {'email': email});
  }

  /// Requests an account-deletion email. The emailed link opens the web app,
  /// where the user confirms the irreversible deletion. Same contract as
  /// [requestPasswordReset], plus `account_already_deleted`.
  Future<void> requestAccountDeletion({required String email}) async {
    await _postJson('/v1/account-deletion/request', {'email': email});
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
      localAccountId: const Uuid().v4(),
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
    unawaited(_authStateSub?.cancel());
    unawaited(_detachAuth());
    _http.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// The body fields that put an auth request in promotion mode: the backend
  /// then refuses to sign in to a pre-existing online account. Empty for an
  /// ordinary sign-in.
  Map<String, Object?> _promotionFields(LocalPromotion? promotion) {
    if (promotion == null) return const {};
    final local = _accounts.firstWhere(
      (a) => a.id == promotion.accountId && a.type == AccountType.local,
      orElse: () => throw StateError(
        'Promotion requires a local account: ${promotion.accountId}',
      ),
    );
    final localAccountId = local.localAccountId;
    if (localAccountId == null) {
      throw StateError('Local account has no localAccountId: ${local.id}');
    }
    return {'promoteLocalAccountId': localAccountId};
  }

  /// Converts the local account in place: same [UserAccount.id] — it names the
  /// on-device database, so the data never moves — but now a remote account
  /// carrying the server's user id and the new session.
  ///
  /// Remote accounts attach a sync engine, voice sync and server-backed
  /// settings when their subtree is built, and the subtree is only rebuilt
  /// when the account changes. So the local subtree is taken down first, for
  /// one frame, and only then rebuilt as a remote one over the same database
  /// file: reopening it in the frame its predecessor is torn down in is the
  /// two-connections-to-one-file case `_AuthGate` warns about.
  Future<UserAccount> _promoteInPlace(
    LocalPromotion promotion,
    Map<String, Object?> body,
  ) async {
    final userJson = body['user'] as Map<String, Object?>?;
    if (userJson == null) {
      throw StateError('Sign-in response missing user');
    }
    final serverId = userJson['id'] as String;
    final index = _accounts.indexWhere(
      (a) => a.id == promotion.accountId && a.type == AccountType.local,
    );
    if (index == -1) {
      throw StateError('Promoted account is gone: ${promotion.accountId}');
    }
    final local = _accounts[index];

    // The server only lets a promotion through for an account this very
    // promotion created, but the user may since have signed into it from the
    // regular sign-in screen. Two entries for one user would split its data.
    if (_accounts.any((a) => a.id == serverId || a.remoteUserId == serverId)) {
      throw AccountAlreadyAddedError(userJson['email'] as String?);
    }

    await promotion.beforeConvert();

    final promoted = UserAccount(
      id: local.id,
      type: AccountType.remote,
      // The user named this account when they made it; keep that over
      // whatever the identity provider calls them.
      name: local.name ?? userJson['name'] as String?,
      email: userJson['email'] as String?,
      picture: userJson['image'] as String?,
      sessionToken: body['refreshToken'] as String,
      remoteUserId: serverId,
    );

    _promotingId = local.id;
    notifyListeners();
    try {
      await _awaitFrame();
      _accounts = [
        for (final a in _accounts)
          if (a.id == local.id) promoted else a,
      ];
      _activeId = promoted.id;
      await _persist();
      await _attachAuthForActive();
    } finally {
      _promotingId = null;
      notifyListeners();
    }
    return promoted;
  }

  Future<UserAccount> _saveRemoteAccountFromAuthResponse(
    Map<String, Object?> body, {
    bool rejectExisting = false,
    LocalPromotion? promotion,
  }) async {
    if (promotion != null) return _promoteInPlace(promotion, body);

    final userJson = body['user'] as Map<String, Object?>?;
    if (userJson == null) {
      throw StateError('Sign-in response missing user');
    }

    final serverId = userJson['id'] as String;
    // An account promoted from a local one keeps its local id, so signing in
    // again (re-auth after its session died) must land on that entry instead
    // of minting a second, empty one under the server id.
    UserAccount? promotedEntry;
    for (final a in _accounts) {
      if (a.remoteUserId == serverId) promotedEntry = a;
    }
    final account =
        promotedEntry?.copyWith(
          name: userJson['name'] as String?,
          email: userJson['email'] as String?,
          picture: userJson['image'] as String?,
          sessionToken: body['refreshToken'] as String,
          requiresReauth: false,
          serverDeleted: false,
        ) ??
        UserAccount(
          id: serverId,
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

    // Deleting an account server-side and signing up again with the same
    // address mints a *new* user id, so matching on id alone would leave the
    // dead entry behind and append a second one — two accounts, same email.
    // Drop any server-deleted entry for this address (its local database goes
    // with it) so re-signing in replaces the corpse instead of sitting next to
    // it. Live accounts are matched by id exactly as before.
    final email = account.email;
    final supersededIds = [
      for (final a in _accounts)
        if (a.id != account.id &&
            a.serverDeleted &&
            a.type == AccountType.remote &&
            email != null &&
            a.email == email)
          a.id,
    ];
    for (final id in supersededIds) {
      await AppDatabase.deleteForUser(id);
    }

    _accounts = [
      for (final a in _accounts)
        if (a.id != account.id && !supersededIds.contains(a.id)) a,
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
    _convex?.setAuth(fetchToken: _fetchTokenForConvex);
  }

  Future<void> _detachAuth() async {
    if (_convexAuthenticated) {
      _convexAuthenticated = false;
      notifyListeners();
    }
    _convex?.clearAuth();
  }

  /// [TokenFetcher] for the Convex client. Every `/auth/refresh` mints a
  /// fresh 24 h JWT, so `forceRefresh` needs no special handling. Returning
  /// null means "signed out, run unauthenticated": a 401 is a dead or deleted
  /// session that retrying cannot fix (the marked account prompts re-auth),
  /// while transient failures rethrow so the client retries on its own timer.
  Future<String?> _fetchTokenForConvex({required bool forceRefresh}) async {
    try {
      return await _fetchFreshAccessToken();
    } on AuthHttpError catch (e) {
      if (e.statusCode == 401) return null;
      rethrow;
    }
  }

  Future<String?> _fetchFreshAccessToken() async {
    debugPrint('auth: fetching fresh access token');
    final active = activeAccount;
    final session = active?.sessionToken;
    if (active == null || session == null) return null;
    try {
      debugPrint('auth: refreshing access token');
      // `userId` lets the server distinguish a deleted account from an
      // ordinary dead session: the purge deletes refreshTokens first, so by
      // now the token row is gone and the id is all it can look up.
      final body = await _postJson('/auth/refresh', {
        'refreshToken': session,
        'userId': active.serverUserId,
      });
      return body['accessToken'] as String;
    } catch (e) {
      debugPrint('auth: token refresh failed: $e');
      if (e is AuthHttpError && e.statusCode == 401) {
        // Only the explicit code means "deleted". A bare 401 is an expired or
        // revoked session, which stays recoverable by signing in again.
        if (e.code == 'account_deleted') {
          await _markServerDeleted(active.id);
        } else {
          await _markRequiresReauth(active.id);
        }
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

  /// The account was deleted server-side. Also sets [requiresReauth] so sync
  /// stops, but the local database is left untouched: the user keeps offline
  /// access to their data until they choose to remove it from the device.
  Future<void> _markServerDeleted(String accountId) async {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx == -1 || _accounts[idx].serverDeleted) return;
    final updated = [..._accounts];
    updated[idx] = updated[idx].copyWith(
      requiresReauth: true,
      serverDeleted: true,
    );
    _accounts = updated;
    await _persist();
    notifyListeners();
  }

  /// Drops a server-deleted account and its local database from this device.
  /// Deliberately narrow: it refuses any account the server has not confirmed
  /// deleted, so a transient auth failure can never take local data with it.
  Future<void> removeDeletedAccount(String id) async {
    final account = _accounts.firstWhere((a) => a.id == id);
    if (!account.serverDeleted) {
      throw StateError('removeDeletedAccount called on a live account: $id');
    }
    await AppDatabase.deleteForUser(id);
    _accounts = _accounts.where((a) => a.id != id).toList();
    if (_activeId == id) {
      _activeId = null;
      await _detachAuth();
    }
    await _persist();
    notifyListeners();
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final localeTag = _localeTag?.call();
    final response = await _http.post(
      Uri.parse('${AppConfig.convexSiteUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (localeTag != null && localeTag.isNotEmpty)
          'Accept-Language': localeTag,
      },
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

const _nonceAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// A single-use value binding an Apple sign-in request to its response.
/// `Random.secure()` because a guessable nonce is no nonce at all.
String _generateNonce([int length = 32]) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => _nonceAlphabet[random.nextInt(_nonceAlphabet.length)],
  ).join();
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
