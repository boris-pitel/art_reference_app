class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.imageUrl,
    required this.createdAt,
    required this.readAt,
    required this.isMine,
  });

  final String id;
  final String senderId;
  final String? body;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isMine;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final senderId = json['sender_id'];
    final createdAt = json['created_at'];
    final readAt = json['read_at'];

    if (id is! String || id.isEmpty) {
      throw StateError('Invalid message ID returned: $json');
    }

    if (senderId is! String || senderId.isEmpty) {
      throw StateError('Invalid sender_id returned: $json');
    }

    if (createdAt is! String || createdAt.isEmpty) {
      throw StateError('Invalid created_at returned: $json');
    }

    return ChatMessage(
      id: id,
      senderId: senderId,
      body: json['body'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(createdAt),
      readAt: readAt is String ? DateTime.parse(readAt) : null,
      isMine: json['is_mine'] == true,
    );
  }
}
