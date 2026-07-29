import 'dart:typed_data';

import 'package:storage_client/storage_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import '../utils/performance_profiler.dart';
import 'image_hash_service.dart';
import 'thumbnail_service.dart';

class ImageAssetInfo {
  const ImageAssetInfo({
    required this.id,
    required this.dateAdded,
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  final String id;
  final DateTime dateAdded;
  final String imageUrl;
  final String? thumbnailUrl;
}

class UnsupportedImageFormatException implements Exception {
  const UnsupportedImageFormatException();

  @override
  String toString() {
    return 'This image format is not supported. '
        'Please convert the image to JPEG or PNG and try again.';
  }
}

class ImageAssetService {
  ImageAssetService(this._supabase);

  final SupabaseClient _supabase;

  static const String _userEmail = 'borispitel1@gmail.com';
  static const String _bucketName = 'reference-images';

  String get _userId {
    final normalizedEmail = _userEmail.trim().toLowerCase();

    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$normalizedEmail',
    );
  }

  String get _normalizedUserEmail {
    return _userEmail.trim().toLowerCase();
  }

  Future<String> uploadImage(Uint8List imageBytes, ReferenceCategory category) {
    return _uploadImage(imageBytes: imageBytes, category: category);
  }

  Future<String> uploadAssociatedImage(
    Uint8List imageBytes,
    String parentImageId,
  ) {
    final normalizedParentImageId = parentImageId.trim();

    if (normalizedParentImageId.isEmpty) {
      throw ArgumentError.value(
        parentImageId,
        'parentImageId',
        'The parent image ID cannot be empty.',
      );
    }

    return _uploadImage(
      imageBytes: imageBytes,
      parentImageId: normalizedParentImageId,
    );
  }

  Future<String> _uploadImage({
    required Uint8List imageBytes,
    ReferenceCategory? category,
    String? parentImageId,
  }) async {
    if ((category == null) == (parentImageId == null)) {
      throw ArgumentError(
        'Provide either a category or a parent image ID, but not both.',
      );
    }

    final isAssociatedImage = parentImageId != null;

    final profiler = PerformanceProfiler(
      isAssociatedImage ? 'ASSOCIATED IMAGE UPLOAD' : 'IMAGE UPLOAD',
    );

    try {
      if (imageBytes.isEmpty) {
        throw const UnsupportedImageFormatException();
      }

      profiler.checkpoint(
        'Upload method started; original size: '
        '${(imageBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      late final Uint8List thumbnailBytes;

      try {
        thumbnailBytes = await ThumbnailService.createThumbnail(
          imageBytes,
          maximumDimension: 500,
          jpegQuality: 80,
        );
      } catch (error) {
        profiler.checkpoint('Thumbnail creation failed: $error');

        throw const UnsupportedImageFormatException();
      }

      profiler.checkpoint(
        'Thumbnail created; thumbnail size: '
        '${(thumbnailBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
      );

      if (thumbnailBytes.isEmpty) {
        throw const UnsupportedImageFormatException();
      }

      final imageHash = await ImageHashService.calculateSha256(imageBytes);

      profiler.checkpoint('SHA-256 hash calculated');

      final destinationBody = <String, dynamic>{};

      if (category != null) {
        destinationBody['category_code'] = category.databaseCode;
      } else {
        destinationBody['parent_image_id'] = parentImageId;
      }

      final prepareResponse = await _supabase.functions.invoke(
        'prepare-image-upload',
        body: {
          'user_id': _userId,
          'user_email': _normalizedUserEmail,
          ...destinationBody,
          'image_hash': imageHash,
        },
      );

      profiler.checkpoint('prepare-image-upload completed');

      final prepareData = prepareResponse.data;

      if (prepareData is! Map) {
        throw StateError(
          'prepare-image-upload returned an '
          'unexpected response: $prepareData',
        );
      }

      final preparedImageId = prepareData['image_id'];

      if (preparedImageId is! String || preparedImageId.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return '
          'a valid image ID. '
          'Response: $prepareData',
        );
      }

      final existingImage = prepareData['existing_image'] == true;

      final uploadRequired = prepareData['upload_required'] == true;

      if (existingImage && !uploadRequired) {
        profiler.finish(
          isAssociatedImage
              ? 'Existing image linked to parent; '
                    'physical upload skipped'
              : 'Existing image found; '
                    'physical upload skipped',
        );

        return preparedImageId;
      }

      if (!uploadRequired) {
        throw StateError(
          'prepare-image-upload returned an '
          'inconsistent response. '
          'Response: $prepareData',
        );
      }

      final storagePath = prepareData['storage_path'];
      final uploadToken = prepareData['upload_token'];

      if (storagePath is! String || storagePath.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return '
          'a valid Storage path. '
          'Response: $prepareData',
        );
      }

      if (uploadToken is! String || uploadToken.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return '
          'a valid upload token. '
          'Response: $prepareData',
        );
      }

      await _supabase.storage
          .from(_bucketName)
          .uploadBinaryToSignedUrl(
            storagePath,
            uploadToken,
            imageBytes,
            FileOptions(
              cacheControl: '3600',
              contentType: _detectContentType(imageBytes),
              upsert: false,
            ),
          );

      profiler.checkpoint(
        'Original image uploaded directly '
        'to Supabase Storage',
      );

      final finalizeResponse = await _supabase.functions.invoke(
        'finalize-image-upload',
        body: {
          'user_id': _userId,
          'user_email': _normalizedUserEmail,
          ...destinationBody,
          'image_hash': imageHash,
          'image_id': preparedImageId,
          'storage_path': storagePath,
        },
      );

      profiler.checkpoint('finalize-image-upload completed');

      final finalizeData = finalizeResponse.data;

      if (finalizeData is! Map) {
        throw StateError(
          'finalize-image-upload returned '
          'an unexpected response: '
          '$finalizeData',
        );
      }

      if (finalizeData['finalized'] != true) {
        throw StateError(
          'The original image was uploaded, '
          'but finalization failed. '
          'Response: $finalizeData',
        );
      }

      final finalizedImageId = finalizeData['image_id'];

      if (finalizedImageId is! String || finalizedImageId.isEmpty) {
        throw StateError(
          'finalize-image-upload did not '
          'return a valid image ID. '
          'Response: $finalizeData',
        );
      }

      final imageAlreadyExisted = finalizeData['existing_image'] == true;

      if (imageAlreadyExisted) {
        profiler.finish(
          isAssociatedImage
              ? 'Existing image linked during '
                    'finalization; thumbnail upload skipped'
              : 'Existing image found during '
                    'finalization; thumbnail upload skipped',
        );

        return finalizedImageId;
      }

      final thumbnailResponse = await _supabase.functions.invoke(
        'upload-thumbnail',
        body: thumbnailBytes,
        headers: {
          'Content-Type': 'image/jpeg',
          'x-user-id': _userId,
          'x-image-id': finalizedImageId,
        },
      );

      profiler.checkpoint('Thumbnail uploaded');

      final thumbnailData = thumbnailResponse.data;

      if (thumbnailData is! Map || thumbnailData['thumbnail_saved'] != true) {
        throw StateError(
          'The original image was saved, '
          'but its thumbnail could not be saved. '
          'Response: $thumbnailData',
        );
      }

      profiler.finish();

      return finalizedImageId;
    } catch (error) {
      profiler.fail(error);
      rethrow;
    }
  }

  Future<void> removeImageFromCategory(
    String imageId,
    ReferenceCategory category,
  ) async {
    final normalizedImageId = imageId.trim();

    if (normalizedImageId.isEmpty) {
      throw ArgumentError.value(
        imageId,
        'imageId',
        'The image ID cannot be empty.',
      );
    }

    final response = await _supabase.functions.invoke(
      'remove-image-from-category',
      body: {
        'user_id': _userId,
        'image_id': normalizedImageId,
        'category_code': category.databaseCode,
      },
    );

    final data = response.data;

    if (data is! Map) {
      throw StateError(
        'remove-image-from-category returned '
        'an unexpected response: $data',
      );
    }

    if (data['removed'] != true) {
      throw StateError(
        data['error']?.toString() ??
            'The image was not removed '
                'from the category.',
      );
    }
  }

  Future<void> removeAssociatedImage({
    required String parentImageId,
    required String childImageId,
  }) async {
    final normalizedParentImageId = parentImageId.trim();

    final normalizedChildImageId = childImageId.trim();

    if (normalizedParentImageId.isEmpty) {
      throw ArgumentError.value(
        parentImageId,
        'parentImageId',
        'The parent image ID cannot be empty.',
      );
    }

    if (normalizedChildImageId.isEmpty) {
      throw ArgumentError.value(
        childImageId,
        'childImageId',
        'The associated image ID cannot be empty.',
      );
    }

    if (normalizedParentImageId == normalizedChildImageId) {
      throw ArgumentError(
        'The parent image and associated image '
        'cannot have the same ID.',
      );
    }

    final response = await _supabase.functions.invoke(
      'remove-associated-image',
      method: HttpMethod.post,
      headers: {
        'x-user-id': _userId,
        'x-parent-image-id': normalizedParentImageId,
        'x-child-image-id': normalizedChildImageId,
      },
    );

    final data = response.data;

    if (data is! Map) {
      throw StateError(
        'remove-associated-image returned '
        'an unexpected response: $data',
      );
    }

    if (data['removed'] != true) {
      throw StateError(
        data['error']?.toString() ?? 'The associated image was not removed.',
      );
    }
  }

  Future<List<ImageAssetInfo>> listImages(ReferenceCategory category) async {
    final cacheBuster = DateTime.now().millisecondsSinceEpoch;

    final response = await _supabase.functions.invoke(
      'list-images?refresh=$cacheBuster',
      method: HttpMethod.get,
      headers: {'x-user-id': _userId, 'x-category-code': category.databaseCode},
    );

    final data = response.data;

    if (data is! List) {
      throw StateError(
        'The list-images function returned '
        'an unexpected response: $data',
      );
    }

    return _parseImageAssetList(data, responseName: 'list-images');
  }

  Future<List<ImageAssetInfo>> listAssociatedImages(
    String parentImageId,
  ) async {
    final normalizedParentImageId = parentImageId.trim();

    if (normalizedParentImageId.isEmpty) {
      throw ArgumentError.value(
        parentImageId,
        'parentImageId',
        'The parent image ID cannot be empty.',
      );
    }

    final cacheBuster = DateTime.now().millisecondsSinceEpoch;

    final response = await _supabase.functions.invoke(
      'list-associated-images?refresh=$cacheBuster',
      method: HttpMethod.get,
      headers: {
        'x-user-id': _userId,
        'x-parent-image-id': normalizedParentImageId,
      },
    );

    final data = response.data;

    if (data is! List) {
      throw StateError(
        'The list-associated-images function '
        'returned an unexpected response: $data',
      );
    }

    return _parseImageAssetList(data, responseName: 'list-associated-images');
  }

  List<ImageAssetInfo> _parseImageAssetList(
    List<dynamic> data, {
    required String responseName,
  }) {
    return data.map((item) {
      if (item is! Map) {
        throw StateError(
          'An entry returned by $responseName '
          'had an unexpected type: '
          '${item.runtimeType}',
        );
      }

      final row = Map<String, dynamic>.from(item);

      final id = row['id'];
      final dateAdded = row['date_added'];
      final imageUrl = row['image_url'];
      final thumbnailUrl = row['thumbnail_url'];

      if (id is! String || id.isEmpty) {
        throw StateError(
          'Invalid image ID returned by '
          '$responseName: $row',
        );
      }

      if (dateAdded is! String || dateAdded.isEmpty) {
        throw StateError(
          'Invalid date_added returned by '
          '$responseName: $row',
        );
      }

      if (imageUrl is! String || imageUrl.isEmpty) {
        throw StateError(
          'Missing image_url returned by '
          '$responseName: $row',
        );
      }

      if (thumbnailUrl != null && thumbnailUrl is! String) {
        throw StateError(
          'Invalid thumbnail_url returned by '
          '$responseName: $row',
        );
      }

      DateTime parsedDateAdded;

      try {
        parsedDateAdded = DateTime.parse(dateAdded);
      } catch (error) {
        throw StateError(
          'Unable to parse date_added returned '
          'by $responseName: $dateAdded. '
          'Error: $error',
        );
      }

      return ImageAssetInfo(
        id: id,
        dateAdded: parsedDateAdded,
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl as String?,
      );
    }).toList();
  }

  String _detectContentType(Uint8List imageBytes) {
    if (imageBytes.length >= 3 &&
        imageBytes[0] == 0xff &&
        imageBytes[1] == 0xd8 &&
        imageBytes[2] == 0xff) {
      return 'image/jpeg';
    }

    if (imageBytes.length >= 8 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4e &&
        imageBytes[3] == 0x47 &&
        imageBytes[4] == 0x0d &&
        imageBytes[5] == 0x0a &&
        imageBytes[6] == 0x1a &&
        imageBytes[7] == 0x0a) {
      return 'image/png';
    }

    return 'application/octet-stream';
  }
}
