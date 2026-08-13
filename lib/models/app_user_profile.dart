import 'package:supabase_flutter/supabase_flutter.dart';

class AppUserProfile {
  const AppUserProfile({
    required this.authUserId,
    required this.email,
    required this.loginName,
    required this.isAdmin,
  });

  final String authUserId;
  final String? email;
  final String? loginName;
  final bool isAdmin;

  factory AppUserProfile.fromAuthUser(User user) {
    final rawLoginName = user.userMetadata?['login_name']?.toString().trim();
    return AppUserProfile(
      authUserId: user.id,
      email: user.email,
      loginName: rawLoginName == null || rawLoginName.isEmpty
          ? null
          : rawLoginName,
      isAdmin: user.appMetadata['is_admin'] == true,
    );
  }

  factory AppUserProfile.fromJson(Map<String, dynamic> json) {
    final rawLoginName = json['login_name']?.toString().trim();
    return AppUserProfile(
      authUserId: (json['auth_user_id'] ?? json['id']).toString(),
      email: json['email']?.toString(),
      loginName: rawLoginName == null || rawLoginName.isEmpty
          ? null
          : rawLoginName,
      isAdmin: json['is_admin'] == true,
    );
  }
}
