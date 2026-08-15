import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../navigation.dart';

/// Tracks an in-progress admin impersonation session (started from the
/// Maintenance screen) so a persistent banner can be shown across the whole
/// app and the admin's own session can be restored afterward.
class ImpersonationController {
  ImpersonationController._();

  static final ImpersonationController instance = ImpersonationController._();

  final ValueNotifier<String?> impersonatedEmail = ValueNotifier<String?>(
    null,
  );

  String? _originalRefreshToken;

  bool get isActive => impersonatedEmail.value != null;

  void begin({
    required String targetEmail,
    required String originalRefreshToken,
  }) {
    _originalRefreshToken = originalRefreshToken;
    impersonatedEmail.value = targetEmail;
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  Future<void> returnToOriginalAccount() async {
    final refreshToken = _originalRefreshToken;
    if (refreshToken == null) return;
    await Supabase.instance.client.auth.setSession(refreshToken);
    _originalRefreshToken = null;
    impersonatedEmail.value = null;
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}
