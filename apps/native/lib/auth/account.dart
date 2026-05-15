enum AccountType { local, remote }

class UserAccount {
  const UserAccount({
    required this.id,
    required this.type,
    this.name,
    this.email,
    this.token,
    this.picture,
    this.requiresReauth = false,
  });

  final String id;
  final AccountType type;
  final String? name;
  final String? email;
  final String? token;
  final String? picture;
  // Server says this session is dead, but we keep the account locally so the
  // user is never locked out — offline mode still works.
  final bool requiresReauth;

  UserAccount copyWith({
    String? name,
    String? email,
    String? token,
    String? picture,
    bool? requiresReauth,
  }) {
    return UserAccount(
      id: id,
      type: type,
      name: name ?? this.name,
      email: email ?? this.email,
      token: token ?? this.token,
      picture: picture ?? this.picture,
      requiresReauth: requiresReauth ?? this.requiresReauth,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'email': email,
    'token': token,
    'picture': picture,
    'requiresReauth': requiresReauth,
  };

  factory UserAccount.fromJson(Map<String, Object?> json) {
    return UserAccount(
      id: json['id'] as String,
      type: AccountType.values.firstWhere((t) => t.name == json['type']),
      name: json['name'] as String?,
      email: json['email'] as String?,
      token: json['token'] as String?,
      picture: json['picture'] as String?,
      requiresReauth: json['requiresReauth'] as bool? ?? false,
    );
  }
}
