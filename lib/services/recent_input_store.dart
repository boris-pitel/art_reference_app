import 'package:shared_preferences/shared_preferences.dart';

/// Device-local histories for text that is useful to reuse.
///
/// Passwords, tokens, and generated images never belong here. These lists only
/// contain login email addresses and AI instructions the person already typed.
class RecentInputStore {
  static const _loginEmailsKey = 'recent_login_emails';
  static const _aiPromptsKey = 'recent_ai_edit_prompts';

  static const int _maxLoginEmails = 5;
  static const int _maxAiPrompts = 10;

  static Future<List<String>> loginEmails() => _read(_loginEmailsKey);

  static Future<List<String>> aiPrompts() => _read(_aiPromptsKey);

  static Future<List<String>> rememberLoginEmail(String email) {
    return _remember(
      key: _loginEmailsKey,
      value: email.trim().toLowerCase(),
      limit: _maxLoginEmails,
      caseInsensitive: true,
    );
  }

  static Future<List<String>> rememberAiPrompt(String prompt) {
    return _remember(
      key: _aiPromptsKey,
      value: prompt.trim(),
      limit: _maxAiPrompts,
    );
  }

  static Future<List<String>> _read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return List<String>.unmodifiable(
      preferences.getStringList(key) ?? const <String>[],
    );
  }

  static Future<List<String>> _remember({
    required String key,
    required String value,
    required int limit,
    bool caseInsensitive = false,
  }) async {
    if (value.isEmpty) return _read(key);

    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getStringList(key) ?? const <String>[];
    final normalizedValue = caseInsensitive ? value.toLowerCase() : value;
    final updated = <String>[
      value,
      ...existing.where((item) {
        final normalizedItem = caseInsensitive ? item.toLowerCase() : item;
        return normalizedItem != normalizedValue;
      }),
    ].take(limit).toList(growable: false);

    await preferences.setStringList(key, updated);
    return List<String>.unmodifiable(updated);
  }
}
