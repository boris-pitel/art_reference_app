import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum FeedbackType { suggestion, problem, question, other }

extension FeedbackTypeLabel on FeedbackType {
  String get label => switch (this) {
    FeedbackType.suggestion => 'Suggestion',
    FeedbackType.problem => 'Problem',
    FeedbackType.question => 'Question',
    FeedbackType.other => 'Other',
  };
}

class FeedbackService {
  FeedbackService(this._client);
  final SupabaseClient _client;
  static const _uuid = Uuid();
  static const _bucket = 'feedback-attachments';
  static const _appVersion = '1.0.0+1';

  Future<void> submit({
    required FeedbackType type,
    required String comment,
    required String currentScreen,
    XFile? attachment,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) {
      throw StateError('You must be signed in to send feedback.');
    }
    final normalizedComment = comment.trim();
    if (normalizedComment.isEmpty || normalizedComment.length > 5000) {
      throw ArgumentError(
        'Comments must contain between 1 and 5000 characters.',
      );
    }
    final feedbackId = _uuid.v4();
    String? attachmentPath;
    if (attachment != null) {
      final length = await attachment.length();
      if (length > 10 * 1024 * 1024) {
        throw ArgumentError('The screenshot must be 10 MB or smaller.');
      }
      final extension = _supportedExtension(attachment);
      attachmentPath = '${user.id}/$feedbackId.$extension';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            attachmentPath,
            await attachment.readAsBytes(),
            fileOptions: FileOptions(
              contentType: _contentType(extension),
              upsert: false,
            ),
          );
    }
    try {
      await _client.from('user_feedback').insert({
        'id': feedbackId,
        'user_id': user.id,
        'user_email': user.email,
        'feedback_type': type.name,
        'comment': normalizedComment,
        'platform': _platformName(),
        'app_version': _appVersion,
        'current_screen': currentScreen,
        'attachment_path': attachmentPath,
        'metadata': {'is_web': kIsWeb},
      });
    } catch (_) {
      if (attachmentPath != null) {
        try {
          await _client.storage.from(_bucket).remove([attachmentPath]);
        } catch (_) {
          // Preserve the original database error.
        }
      }
      rethrow;
    }
  }

  String _supportedExtension(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    if (extension == 'jpg' || extension == 'jpeg') return 'jpg';
    if (extension == 'png' || extension == 'webp') return extension;
    throw ArgumentError('Screenshots must be JPEG, PNG, or WebP images.');
  }

  String _contentType(String extension) => switch (extension) {
    'jpg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'application/octet-stream',
  };

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
