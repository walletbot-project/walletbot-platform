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

  UserAccount copyWith({
    String? name,
    String? email,
    String? picture,
    String? sessionToken,
    bool? requiresReauth,
    bool? serverDeleted,
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
    );
  }
}
