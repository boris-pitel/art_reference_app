import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ImageAssetInfo {
  const ImageAssetInfo({required this.id, required this.dateAdded});

  final String id;
  final DateTime dateAdded;
}

class ImageAssetService {
  ImageAssetService(this._supabase);

  final SupabaseClient _supabase;

  static const String _userEmail = 'borispitel1@gmail.com';

  String get _userId {
    final normalizedEmail = _userEmail.trim().toLowerCase();

    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$normalizedEmail',
    );
  }

  Future<String> uploadImage(Uint8List imageBytes) async {
    final response = await _supabase.functions.invoke(
      'upload-image',
      body: imageBytes,
      headers: {
        'Content-Type': 'application/octet-stream',
        'x-user-id': _userId,
        'x-user-email': _userEmail.trim().toLowerCase(),
      },
    );

    final data = response.data;

    if (data is! Map || data['id'] == null) {
      throw StateError(
        'The upload function returned an unexpected response: $data',
      );
    }

    return data['id'] as String;
  }

  Future<List<ImageAssetInfo>> listImages() async {
    final response = await _supabase.functions.invoke(
      'list-images',
      method: HttpMethod.get,
      headers: {'x-user-id': _userId},
    );

    final data = response.data;

    if (data is! List) {
      throw StateError(
        'The list function returned an unexpected response: $data',
      );
    }

    return data.map((item) {
      final row = item as Map<String, dynamic>;

      return ImageAssetInfo(
        id: row['id'] as String,
        dateAdded: DateTime.parse(row['date_added'] as String),
      );
    }).toList();
  }

  Future<Uint8List> downloadImage(String imageId) async {
    final response = await _supabase.functions.invoke(
      'get-image?id=$imageId',
      method: HttpMethod.get,
      headers: {'x-user-id': _userId},
    );

    final data = response.data;

    if (data is Uint8List) {
      return data;
    }

    if (data is List<int>) {
      return Uint8List.fromList(data);
    }

    throw StateError(
      'The image function returned an unexpected response: ${data.runtimeType}',
    );
  }
}
