import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum AiImageQuality {
  low('Low', 'Fast preview'),
  medium('Medium', 'Recommended'),
  high('High', 'Best detail');

  const AiImageQuality(this.label, this.description);
  final String label;
  final String description;
}

class AiImageEditService {
  AiImageEditService(this._supabase);

  final SupabaseClient _supabase;

  String get _userId {
    final email = _supabase.auth.currentUser?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      throw StateError('You must be signed in before using AI editing.');
    }
    return const Uuid().v5(Namespace.url.value, 'art-reference-user:$email');
  }

  Future<Uint8List> editImage({
    required String imageId,
    required String prompt,
    required AiImageQuality quality,
  }) async {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError('Describe the change you want AI to make.');
    }
    if (normalizedPrompt.length > 1000) {
      throw ArgumentError('The AI edit prompt cannot exceed 1,000 characters.');
    }
    final response = await _supabase.functions.invoke(
      'ai-edit-image',
      body: {
        'imageId': imageId,
        'prompt': normalizedPrompt,
        'quality': quality.name,
      },
      headers: {'x-user-id': _userId},
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('AI editing returned an unexpected response.');
    }
    if (data['success'] != true) {
      throw StateError(data['error']?.toString() ?? 'AI editing failed.');
    }
    final encoded = data['image_base64'];
    if (encoded is! String || encoded.isEmpty) {
      throw StateError('AI editing did not return an image.');
    }
    return base64Decode(encoded);
  }
}
