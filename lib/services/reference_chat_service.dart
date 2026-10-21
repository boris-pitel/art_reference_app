import 'package:supabase_flutter/supabase_flutter.dart';

class ReferenceChatService {
  ReferenceChatService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>> call(
    String referenceId,
    String action, [
    Map<String, dynamic> values = const {},
  ]) async {
    if (_client.auth.currentUser?.appMetadata['is_admin'] != true) {
      throw StateError('Administrator access required.');
    }
    try {
      final response = await _client.functions.invoke(
        'reference-ai-chat',
        body: {'referenceId': referenceId, 'action': action, ...values},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw StateError(data['error'].toString());
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(
        details is Map && details['error'] != null
            ? details['error'].toString()
            : 'Unable to reach reference chat. Please try again.',
      );
    }
  }
}
