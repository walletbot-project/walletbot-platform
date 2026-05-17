enum AccountType { local, remote }

class UserAccount {
  const UserAccount({
    required this.id,
    required this.type,
    this.name,
    this.email,
    this.picture,
    this.accessToken,
    this.accessTokenExpiresAt,
    this.refreshToken,
    this.requiresReauth = false,
  });

  final String id;
  final AccountType type;
  final String? name;
  final String? email;
  final String? picture;

  /// JWT signed by our backend ([CONVEX_SITE_URL]/native-auth issuer). Passed
  /// to Convex via `setAuth` so `ctx.auth.getUserIdentity()` resolves.
  final String? accessToken;

  /// ms-epoch expiry of [accessToken] as reported by the backend at issue time.
  final int? accessTokenExpiresAt;

  /// Long-lived opaque session secret. Posted to `/auth/refresh` to mint a
  /// fresh [accessToken]. Not rotated — stays valid until explicitly revoked
  /// (signout, "remove this device").
  final String? refreshToken;

  /// Server says this session is dead (token revoked). We keep the account
  /// locally so the user is never locked out — offline mode still works.
  final bool requiresReauth;

  UserAccount copyWith({
    String? name,
    String? email,
    String? picture,
    String? accessToken,
    int? accessTokenExpiresAt,
    String? refreshToken,
    bool? requiresReauth,
  }) {
    return UserAccount(
      id: id,
      type: type,
      name: name ?? this.name,
      email: email ?? this.email,
      picture: picture ?? this.picture,
      accessToken: accessToken ?? this.accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshToken: refreshToken ?? this.refreshToken,
      requiresReauth: requiresReauth ?? this.requiresReauth,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'email': email,
    'picture': picture,
    'accessToken': accessToken,
    'accessTokenExpiresAt': accessTokenExpiresAt,
    'refreshToken': refreshToken,
    'requiresReauth': requiresReauth,
  };

  factory UserAccount.fromJson(Map<String, Object?> json) {
    return UserAccount(
      id: json['id'] as String,
      type: AccountType.values.firstWhere((t) => t.name == json['type']),
      name: json['name'] as String?,
      email: json['email'] as String?,
      picture: json['picture'] as String?,
      accessToken: json['accessToken'] as String?,
      accessTokenExpiresAt: (json['accessTokenExpiresAt'] as num?)?.toInt(),
      refreshToken: json['refreshToken'] as String?,
      requiresReauth: json['requiresReauth'] as bool? ?? false,
    );
  }
}
