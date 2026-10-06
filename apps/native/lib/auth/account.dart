enum AccountType { local, remote }

class UserAccount {
  const UserAccount({
    required this.id,
    required this.type,
    this.name,
    this.email,
    this.picture,
    this.sessionToken,
    this.requiresReauth = false,
    this.serverDeleted = false,
    this.localAccountId,
  });

  final String id;
  final AccountType type;
  final String? name;
  final String? email;
  final String? picture;

  /// Long-lived opaque session secret. Exchanged for short-lived Convex JWTs
  /// via `POST /auth/refresh`. Not rotated — stays valid until explicitly
  /// revoked (signout, "remove this device").
  final String? sessionToken;

  /// Server says this session is dead (token revoked). We keep the account
  /// locally so the user is never locked out — offline mode still works.
  final bool requiresReauth;

  /// The server confirmed this user was **deleted** (`account_deleted` from
  /// `POST /auth/refresh`), not merely signed out. Signing in again would mint
  /// a brand-new user for the same address instead of restoring this one, so
  /// the only honest offers are "remove from this device" or staying offline.
  /// Set exclusively from that explicit code — never inferred from a bare 401,
  /// which is an ordinary expired session.
  final bool serverDeleted;

  /// LOCAL accounts only: a random v4 UUID that names the account to the
  /// backend's `appUsers` (as `local:<UUID>`), so accounts on one device
  /// can be told apart without sending anything about them. Separate from [id],
  /// which names the account's on-device database and must never change.
  /// Null on accounts created before it existed until [AuthController.load]
  /// assigns one.
  final String? localAccountId;

  UserAccount copyWith({
    String? name,
    String? email,
    String? picture,
    String? sessionToken,
    bool? requiresReauth,
    bool? serverDeleted,
    String? localAccountId,
  }) {
    return UserAccount(
      id: id,
      type: type,
      name: name ?? this.name,
      email: email ?? this.email,
      picture: picture ?? this.picture,
      sessionToken: sessionToken ?? this.sessionToken,
      requiresReauth: requiresReauth ?? this.requiresReauth,
      serverDeleted: serverDeleted ?? this.serverDeleted,
      localAccountId: localAccountId ?? this.localAccountId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'email': email,
    'picture': picture,
    'sessionToken': sessionToken,
    'requiresReauth': requiresReauth,
    'serverDeleted': serverDeleted,
    'localAccountId': localAccountId,
  };

  factory UserAccount.fromJson(Map<String, Object?> json) {
    return UserAccount(
      id: json['id'] as String,
      type: AccountType.values.firstWhere((t) => t.name == json['type']),
      name: json['name'] as String?,
      email: json['email'] as String?,
      picture: json['picture'] as String?,
      // Accept legacy `refreshToken` key from pre-setAuthWithRefresh storage.
      sessionToken: (json['sessionToken'] ?? json['refreshToken']) as String?,
      requiresReauth: json['requiresReauth'] as bool? ?? false,
      serverDeleted: json['serverDeleted'] as bool? ?? false,
      localAccountId: json['localAccountId'] as String?,
    );
  }
}
