import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The identity whose downloaded library is currently open on this device.
///
/// Supabase is still the authority for an online session. This class only
/// remembers enough identity to select the right on-device data after the
/// user has explicitly signed out and later opens the app without a network.
class CachedUserIdentity {
  const CachedUserIdentity({required this.userId, required this.email});

  final String userId;
  final String email;

  Map<String, String> toJson() => {'user_id': userId, 'email': email};

  factory CachedUserIdentity.fromJson(Map<String, dynamic> json) {
    final userId = (json['user_id'] as String? ?? '').trim();
    final email = (json['email'] as String? ?? '').trim().toLowerCase();
    if (userId.isEmpty || email.isEmpty) {
      throw const FormatException('Cached user identity is incomplete.');
    }
    return CachedUserIdentity(userId: userId, email: email);
  }
}

class LocalUserSession {
  const LocalUserSession._();

  static const String _rememberedUserKey = 'last_authenticated_user_v1';

  static CachedUserIdentity? _rememberedUser;
  static CachedUserIdentity? _onlineUser;
  static bool _offlineActive = false;
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void _notify() {
    changes.value += 1;
  }

  static CachedUserIdentity? get rememberedUser => _rememberedUser;
  static bool get isOfflineActive => _offlineActive;

  static String? get effectiveUserId {
    final online = _onlineUser;
    if (online != null) return online.userId;
    return _offlineActive ? _rememberedUser?.userId : null;
  }

  static String? get effectiveEmail {
    final online = _onlineUser?.email;
    if (online != null) return online;
    return _offlineActive ? _rememberedUser?.email : null;
  }

  static Future<void> initialize() async {
    _rememberedUser = null;
    _onlineUser = null;
    _offlineActive = false;
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_rememberedUserKey);
    if (value == null) return;
    try {
      _rememberedUser = CachedUserIdentity.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      await preferences.remove(_rememberedUserKey);
      _rememberedUser = null;
    }
  }

  static Future<void> rememberOnlineUser(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    final identity = CachedUserIdentity(userId: user.id, email: email);
    _rememberedUser = identity;
    _onlineUser = identity;
    _offlineActive = false;
    await (await SharedPreferences.getInstance()).setString(
      _rememberedUserKey,
      jsonEncode(identity.toJson()),
    );
    _notify();
  }

  /// Opens the remembered device library. No password is accepted or checked:
  /// this is a local library selection, not a substitute server sign-in.
  static bool activateOffline(String email) {
    final remembered = _rememberedUser;
    if (remembered == null || remembered.email != email.trim().toLowerCase()) {
      return false;
    }
    _offlineActive = true;
    _notify();
    return true;
  }

  static void deactivateOffline() {
    if (!_offlineActive) return;
    _offlineActive = false;
    _notify();
  }

  static void markOnlineSignedOut() {
    if (_onlineUser == null && !_offlineActive) return;
    _onlineUser = null;
    _offlineActive = false;
    _notify();
  }

  static Future<void> forget({String? userId}) async {
    final remembered = _rememberedUser;
    if (userId != null && remembered?.userId != userId) return;
    _offlineActive = false;
    _onlineUser = null;
    _rememberedUser = null;
    await (await SharedPreferences.getInstance()).remove(_rememberedUserKey);
    _notify();
  }
}
