class ReferenceCategory {
  const ReferenceCategory({
    required this.id,
    required this.databaseCode,
    required this.displayName,
    required this.isBuiltIn,
    this.thumbnailAsset,
    this.userId,
  });

  final int id;
  final String databaseCode;
  final String displayName;
  final bool isBuiltIn;
  final String? thumbnailAsset;
  final String? userId;

  bool get canDelete => !isBuiltIn;

  bool get canRename => !isBuiltIn;

  factory ReferenceCategory.fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];

    if (rawId is! num) {
      throw const FormatException(
        'The category record does not contain a valid integer ID.',
      );
    }

    final String databaseCode = (json['code'] as String? ?? '').trim();

    final String displayName = (json['display_name'] as String? ?? '').trim();

    if (databaseCode.isEmpty) {
      throw const FormatException(
        'The category record does not contain a code.',
      );
    }

    if (displayName.isEmpty) {
      throw const FormatException(
        'The category record does not contain a display name.',
      );
    }

    return ReferenceCategory(
      id: rawId.toInt(),
      databaseCode: databaseCode,
      displayName: displayName,
      thumbnailAsset: json['thumbnail_asset'] as String?,
      isBuiltIn: json['is_builtin'] as bool? ?? false,
      userId: json['user_id'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson({required String ownerUserId}) {
    if (isBuiltIn) {
      throw StateError('Built-in categories cannot be created by the user.');
    }

    return <String, dynamic>{
      'user_id': ownerUserId,
      'code': databaseCode,
      'display_name': displayName,
      'thumbnail_asset': thumbnailAsset,
      'is_builtin': false,
    };
  }

  ReferenceCategory copyWith({
    int? id,
    String? databaseCode,
    String? displayName,
    bool? isBuiltIn,
    String? thumbnailAsset,
    String? userId,
  }) {
    return ReferenceCategory(
      id: id ?? this.id,
      databaseCode: databaseCode ?? this.databaseCode,
      displayName: displayName ?? this.displayName,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
      userId: userId ?? this.userId,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReferenceCategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ReferenceCategory('
        'id: $id, '
        'databaseCode: $databaseCode, '
        'displayName: $displayName, '
        'isBuiltIn: $isBuiltIn'
        ')';
  }
}
