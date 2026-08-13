class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.otherUserId,
    required this.otherLoginName,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  final String conversationId;
  final String otherUserId;
  final String? otherLoginName;
  final String? lastMessagePreview;
  final DateTime lastMessageAt;
  final int unreadCount;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final conversationId = json['conversation_id'];
    final otherUserId = json['other_user_id'];
    final lastMessageAt = json['last_message_at'];
    final unreadCount = json['unread_count'];

    if (conversationId is! String || conversationId.isEmpty) {
      throw StateError('Invalid conversation_id returned: $json');
    }

    if (otherUserId is! String || otherUserId.isEmpty) {
      throw StateError('Invalid other_user_id returned: $json');
    }

    if (lastMessageAt is! String || lastMessageAt.isEmpty) {
      throw StateError('Invalid last_message_at returned: $json');
    }

    if (unreadCount is! num) {
      throw StateError('Invalid unread_count returned: $json');
    }

    return ConversationSummary(
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherLoginName: json['other_login_name'] as String?,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageAt: DateTime.parse(lastMessageAt),
      unreadCount: unreadCount.toInt(),
    );
  }
}
