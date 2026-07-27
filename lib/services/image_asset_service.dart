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

  Future<String> uploadImage(
    Uint8List imageBytes,
    ReferenceCategory category,
  ) async {
    final profiler = PerformanceProfiler('IMAGE UPLOAD');

    try {
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

      /*
       * Calculate SHA-256 using a platform-optimized implementation.
       *
       * Chrome uses the browser's native Web Crypto API.
       * Other platforms use the package's appropriate implementation.
       */
      final imageHash = await ImageHashService.calculateSha256(imageBytes);

      profiler.checkpoint('SHA-256 hash calculated');

      final prepareResponse = await _supabase.functions.invoke(
        'prepare-image-upload',
        body: {
          'user_id': _userId,
          'user_email': _normalizedUserEmail,
          'category_code': category.databaseCode,
          'image_hash': imageHash,
        },
      );

      profiler.checkpoint('prepare-image-upload completed');

      final prepareData = prepareResponse.data;

      if (prepareData is! Map) {
        throw StateError(
          'prepare-image-upload returned an unexpected response: '
          '$prepareData',
        );
      }

      final preparedImageId = prepareData['image_id'];

      if (preparedImageId is! String || preparedImageId.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return a valid image ID. '
          'Response: $prepareData',
        );
      }

      final existingImage = prepareData['existing_image'] == true;
      final uploadRequired = prepareData['upload_required'] == true;

      /*
       * The physical image already exists.
       *
       * prepare-image-upload has added the requested category relationship.
       * Do not upload another original or thumbnail.
       */
      if (existingImage && !uploadRequired) {
        profiler.finish('Existing image found; physical upload skipped');

        return preparedImageId;
      }

      if (!uploadRequired) {
        throw StateError(
          'prepare-image-upload returned an inconsistent response. '
          'Response: $prepareData',
        );
      }

      final storagePath = prepareData['storage_path'];
      final uploadToken = prepareData['upload_token'];

      if (storagePath is! String || storagePath.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return a valid Storage path. '
          'Response: $prepareData',
        );
      }

      if (uploadToken is! String || uploadToken.isEmpty) {
        throw StateError(
          'prepare-image-upload did not return a valid upload token. '
          'Response: $prepareData',
        );
      }

      /*
       * Upload the original directly from Flutter to Supabase Storage.
       */
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
        'Original image uploaded directly to Supabase Storage',
      );

      /*
       * Tell the backend that the direct Storage upload completed.
       */
      final finalizeResponse = await _supabase.functions.invoke(
        'finalize-image-upload',
        body: {
          'user_id': _userId,
          'user_email': _normalizedUserEmail,
          'category_code': category.databaseCode,
          'image_hash': imageHash,
          'image_id': preparedImageId,
          'storage_path': storagePath,
        },
      );

      profiler.checkpoint('finalize-image-upload completed');

      final finalizeData = finalizeResponse.data;

      if (finalizeData is! Map) {
        throw StateError(
          'finalize-image-upload returned an unexpected response: '
          '$finalizeData',
        );
      }

      if (finalizeData['finalized'] != true) {
        throw StateError(
          'The original image was uploaded, but finalization failed. '
          'Response: $finalizeData',
        );
      }

      final finalizedImageId = finalizeData['image_id'];

      if (finalizedImageId is! String || finalizedImageId.isEmpty) {
        throw StateError(
          'finalize-image-upload did not return a valid image ID. '
          'Response: $finalizeData',
        );
      }

      final imageAlreadyExisted = finalizeData['existing_image'] == true;

      /*
       * A simultaneous upload may have created the same image first.
       */
      if (imageAlreadyExisted) {
        profiler.finish(
          'Existing image found during finalization; '
          'thumbnail upload skipped',
        );

        return finalizedImageId;
      }

      /*
       * Upload the small thumbnail.
       */
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
          'The original image was saved, but its thumbnail '
          'could not be saved. Response: $thumbnailData',
        );
      }

      profiler.finish();

      return finalizedImageId;
    } catch (error) {
      profiler.fail(error);
      rethrow;
    }
  }

  String _detectContentType(Uint8List imageBytes) {
    /*
     * JPEG begins with FF D8 FF.
     */
    if (imageBytes.length >= 3 &&
        imageBytes[0] == 0xff &&
        imageBytes[1] == 0xd8 &&
        imageBytes[2] == 0xff) {
      return 'image/jpeg';
    }

    /*
     * PNG begins with:
     * 89 50 4E 47 0D 0A 1A 0A
     */
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
        'The list-images function returned an '
        'unexpected response: $data',
      );
    }

    return data.map((item) {
      if (item is! Map) {
        throw StateError(
          'A list-images entry had an unexpected '
          'type: ${item.runtimeType}',
        );
      }

      final row = Map<String, dynamic>.from(item);

      final id = row['id'];
      final dateAdded = row['date_added'];
      final imageUrl = row['image_url'];
      final thumbnailUrl = row['thumbnail_url'];

      if (id is! String || id.isEmpty) {
        throw StateError('Invalid image ID in list response: $row');
      }

      if (dateAdded is! String || dateAdded.isEmpty) {
        throw StateError('Invalid date_added in list response: $row');
      }

      if (imageUrl is! String || imageUrl.isEmpty) {
        throw StateError('Missing image_url in list response: $row');
      }

      if (thumbnailUrl != null && thumbnailUrl is! String) {
        throw StateError('Invalid thumbnail_url in list response: $row');
      }

      return ImageAssetInfo(
        id: id,
        dateAdded: DateTime.parse(dateAdded),
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl as String?,
      );
    }).toList();
  }
}
