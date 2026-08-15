import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceSnapshot {
  const MaintenanceSnapshot({
    required this.users,
    required this.feedback,
    required this.activity,
  });

  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> feedback;
  final List<Map<String, dynamic>> activity;
}

class MaintenanceService {
  MaintenanceService(this._client);

  final SupabaseClient _client;

  Future<MaintenanceSnapshot> load() async {
    final response = await _client.functions.invoke(
      'admin-maintenance',
      method: HttpMethod.get,
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('The maintenance service returned an invalid response.');
    }
    return MaintenanceSnapshot(
      users: _rows(data['users']),
      feedback: _rows(data['feedback']),
      activity: _rows(data['activity']),
    );
  }

  Future<Map<String, dynamic>> loadUserDetails(String userId) async {
    final response = await _client.functions.invoke(
      'admin-maintenance?user_id=${Uri.encodeQueryComponent(userId)}',
      method: HttpMethod.get,
    );
    final data = response.data;
    if (data is! Map || data['user'] is! Map) {
      throw StateError('The maintenance service returned invalid user details.');
    }
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<Map<String, dynamic>> setLoginName({
    required String userId,
    required String? loginName,
  }) async {
    final response = await _client.functions.invoke(
      'admin-maintenance',
      method: HttpMethod.patch,
      body: {'user_id': userId, 'login_name': loginName},
    );
    final data = response.data;
    if (data is! Map || data['user'] is! Map) {
      throw StateError('The maintenance service returned an invalid response.');
    }
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<Map<String, dynamic>> impersonate(String userId) async {
    final response = await _client.functions.invoke(
      'admin-maintenance',
      method: HttpMethod.post,
      body: {'action': 'impersonate', 'user_id': userId},
    );
    final data = response.data;
    if (data is! Map ||
        data['email'] is! String ||
        data['token_hash'] is! String) {
      throw StateError(
        'The maintenance service returned an invalid impersonation response.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> removeUser({required String userId, required String email}) async {
    final response = await _client.functions.invoke(
      'admin-maintenance',
      method: HttpMethod.delete,
      body: {'user_id': userId, 'email': email},
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
