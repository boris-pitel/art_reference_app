import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../models/discoverable_user.dart';
import 'image_asset_service.dart';

class SendMessageResult {
  const SendMessageResult({
    required this.messageId,
    required this.conversationId,
    required this.createdAt,
    this.imageUrl,
  });

  final String messageId;
  final String conversationId;
  final DateTime createdAt;
  final String? imageUrl;
}

class PreparedMessageImageUpload {
  const PreparedMessageImageUpload({
    required this.storagePath,
    required this.uploadToken,
  });

  final String storagePath;
  final String uploadToken;
}

String _extractErrorMessage(Object error) {
  if (error is FunctionException) {
    return switch (error.details) {
      final Map details =>
        details['error']?.toString() ??
            error.reasonPhrase ??
            'Something went wrong.',
      final Object details => details.toString(),
      null => error.reasonPhrase ?? 'Something went wrong.',
    };
  }
  return error.toString();
}

class MessagingService {
  MessagingService(this._supabase);

  final SupabaseClient _supabase;

  static const String _bucketName = 'message-images';

  Future<List<DiscoverableUser>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final response = await _supabase.functions.invoke(
        'search-users?q=${Uri.encodeQueryComponent(trimmed)}',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['users'] is! List) {
        throw StateError('search-users returned an unexpected response: $data');
      }
      return (data['users'] as List)
          .map((row) => DiscoverableUser.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<List<ConversationSummary>> listConversations() async {
    try {
      final response = await _supabase.functions.invoke(
        'list-conversations',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['conversations'] is! List) {
        throw StateError(
          'list-conversations returned an unexpected response: $data',
        );
      }
      return (data['conversations'] as List)
          .map((row) => ConversationSummary.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<List<ChatMessage>> listMessages(String conversationId) async {
    try {
      final response = await _supabase.functions.invoke(
        'list-messages?conversation_id=${Uri.encodeQueryComponent(conversationId)}',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['messages'] is! List) {
        throw StateError('list-messages returned an unexpected response: $data');
      }
      return (data['messages'] as List)
          .map((row) => ChatMessage.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<PreparedMessageImageUpload> prepareImageUpload() async {
    try {
      final response = await _supabase.functions.invoke(
        'prepare-message-image-upload',
      );
      final data = response.data;
      final storagePath = data is Map ? data['storage_path'] : null;
      final uploadToken = data is Map ? data['upload_token'] : null;
      if (storagePath is! String || uploadToken is! String) {
        throw StateError(
          'prepare-message-image-upload returned an unexpected response: $data',
        );
      }
      return PreparedMessageImageUpload(
        storagePath: storagePath,
        uploadToken: uploadToken,
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<void> uploadMessageImageBytes(
    Uint8List bytes,
    PreparedMessageImageUpload prepared,
  ) async {
    try {
      await _supabase.storage.from(_bucketName).uploadBinaryToSignedUrl(
        prepared.storagePath,
        prepared.uploadToken,
        bytes,
        FileOptions(
          cacheControl: '3600',
          contentType: ImageAssetService.detectContentType(bytes),
          upsert: false,
        ),
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<SendMessageResult> sendMessage({
    required String recipientId,
    String? body,
    String? imageStoragePath,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-message',
        body: {
          'recipient_id': recipientId,
          'body': ?body,
          'image_storage_path': ?imageStoragePath,
        },
      );
      final data = response.data;
      final messageId = data is Map ? data['message_id'] : null;
      final conversationId = data is Map ? data['conversation_id'] : null;
      final createdAt = data is Map ? data['created_at'] : null;
      if (messageId is! String || conversationId is! String || createdAt is! String) {
        throw StateError('send-message returned an unexpected response: $data');
      }
      return SendMessageResult(
        messageId: messageId,
        conversationId: conversationId,
        createdAt: DateTime.parse(createdAt),
        imageUrl: data['image_url'] as String?,
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    try {
      await _supabase.functions.invoke(
        'mark-conversation-read',
        body: {'conversation_id': conversationId},
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _supabase.functions.invoke(
        'block-user',
        body: {'user_id': userId},
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _supabase.functions.invoke(
        'unblock-user',
        body: {'user_id': userId},
      );
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<bool> getDiscoverable() async {
    final authUserId = _supabase.auth.currentUser?.id;
    if (authUserId == null) {
      throw StateError('You must be signed in.');
    }
    try {
      final row = await _supabase
          .from('user_profiles')
          .select('is_discoverable')
          .eq('auth_user_id', authUserId)
          .single();
      return row['is_discoverable'] == true;
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<void> setDiscoverable(bool value) async {
    final authUserId = _supabase.auth.currentUser?.id;
    if (authUserId == null) {
      throw StateError('You must be signed in.');
    }
    try {
      await _supabase
          .from('user_profiles')
          .update({'is_discoverable': value})
          .eq('auth_user_id', authUserId);
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }

  Future<List<BlockedUser>> listBlockedUsers() async {
    try {
      final response = await _supabase.functions.invoke(
        'list-blocked-users',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['users'] is! List) {
        throw StateError(
          'list-blocked-users returned an unexpected response: $data',
        );
      }
      return (data['users'] as List)
          .map((row) => BlockedUser.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
    } catch (error) {
      throw StateError(_extractErrorMessage(error));
    }
  }
}
