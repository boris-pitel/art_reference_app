import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Raised when an edit was refused because an allowance ran out.
///
/// Kept distinct from every other failure because it is not one: nothing went
/// wrong, the answer is simply no for now. That difference is what lets the app
/// offer a way forward instead of showing a red line of error text.
class AiQuotaExceeded implements Exception {
  const AiQuotaExceeded({
    required this.message,
    required this.reason,
    this.upgradeName,
    this.upgradeDaily,
    this.upgradeMonthly,
  });

  /// A sentence written for the person reading it.
  final String message;

  /// 'daily', 'monthly', or 'service'.
  final String reason;

  /// The next level up, when there is one. Absent when the ceiling reached is
  /// the service's own, which no amount of upgrading changes.
  final String? upgradeName;
  final int? upgradeDaily;
  final int? upgradeMonthly;

  bool get canUpgrade => reason != 'service' && upgradeName != null;

  static AiQuotaExceeded? fromDetails(FunctionException error) {
    if (error.status != 429) return null;

    final details = error.details;
    if (details is! Map) return null;

    final message = details['error']?.toString();
    if (message == null || message.isEmpty) return null;

    return AiQuotaExceeded(
      message: message,
      reason: details['quota_reason']?.toString() ?? 'daily',
      upgradeName: details['upgrade_name']?.toString(),
      upgradeDaily: details['upgrade_daily'] as int?,
      upgradeMonthly: details['upgrade_monthly'] as int?,
    );
  }

  @override
  String toString() => message;
}

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
    Uint8List? imageBytes,
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
    final FunctionResponse response;

    try {
      response = await _supabase.functions.invoke(
        'ai-edit-image',
        body: {
          'imageId': imageId,
          if (imageBytes != null) 'imageBase64': base64Encode(imageBytes),
          'prompt': normalizedPrompt,
          'quality': quality.name,
        },
        headers: {'x-user-id': _userId},
      );
    } on FunctionException catch (error) {
      final quota = AiQuotaExceeded.fromDetails(error);
      if (quota != null) throw quota;

      // Anything other than a 2xx throws here rather than returning a body, so
      // the readable message the function took care to write is inside the
      // exception. Without this the user is shown
      // "FunctionException(status: 429, details: {...})" — which is how a
      // deliberate, plain-English refusal reaches someone looking like a crash.
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;

      throw StateError(
        message?.isNotEmpty == true
            ? message!
            : 'AI editing failed (${error.status}).',
      );
    }

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
