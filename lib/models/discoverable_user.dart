class DiscoverableUser {
  const DiscoverableUser({required this.id, required this.loginName});

  final String id;
  final String loginName;

  factory DiscoverableUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final loginName = json['login_name'];

    if (id is! String || id.isEmpty) {
      throw StateError('Invalid user ID returned: $json');
    }

    if (loginName is! String || loginName.isEmpty) {
      throw StateError('Invalid login_name returned: $json');
    }

    return DiscoverableUser(id: id, loginName: loginName);
  }
}

class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.loginName,
    required this.blockedAt,
  });

  final String id;
  final String? loginName;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final blockedAt = json['blocked_at'];

    if (id is! String || id.isEmpty) {
      throw StateError('Invalid user ID returned: $json');
    }

    if (blockedAt is! String || blockedAt.isEmpty) {
      throw StateError('Invalid blocked_at returned: $json');
    }

    return BlockedUser(
      id: id,
      loginName: json['login_name'] as String?,
      blockedAt: DateTime.parse(blockedAt),
    );
  }
}
