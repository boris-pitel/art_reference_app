import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import '../utils/performance_profiler.dart';
import 'app_image_cache.dart';
import 'heif_exif_reader.dart';
import 'image_hash_service.dart';
import 'image_import_service.dart';
import 'image_derivatives.dart';
import 'photo_metadata_service.dart';
import 'thumbnail_service.dart';
import 'user_activity_logger.dart';

class ImageAssetInfo {
  const ImageAssetInfo({
    required this.id,
    required this.dateAdded,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.displayUrl,
    this.parentImageId,
    this.parentImageUrl,
  });

  final String id;
  final DateTime dateAdded;
  // The full, original-resolution image. Used for export/share/save/print
  // and as the source for cropping — never swap this for [displayUrl].
  final String imageUrl;
  final String? thumbnailUrl;
  // A ~3072px derivative safe to decode/render on any device. Used only for
  // on-screen viewing (Image.network); falls back to [imageUrl] when null
  // (older images uploaded before this derivative existed).
  final String? displayUrl;
  final String? parentImageId;
  final String? parentImageUrl;
}

/// How many images sit in each category.
///
/// My Art is separate because it is not a stored category: it is derived from
/// finished artworks, and counting it means a different query.
class ImageCategoryCounts {
  const ImageCategoryCounts({
    required this.byCategoryCode,
    required this.finishedArtwork,
    this.ownedImageIds,
  });

  const ImageCategoryCounts.empty()
    : byCategoryCode = const {},
      finishedArtwork = 0,
      ownedImageIds = null;

  final Map<String, int> byCategoryCode;
  final int finishedArtwork;

  /// Every image the user owns, for evicting cached copies of anything deleted
  /// on another device.
  ///
  /// Null when the server did not send it, which is different from empty: an
  /// empty set would mean "this person owns nothing" and would clear the whole
  /// cache. Callers must treat null as "do not evict".
  final Set<String>? ownedImageIds;

  int countFor(ReferenceCategory category) => category.isMyArt
      ? finishedArtwork
      : byCategoryCode[category.databaseCode] ?? 0;
}

class UnsupportedImageFormatException implements Exception {
  const UnsupportedImageFormatException();

  @override
  String toString() {
    return 'This image format is not supported. '
        'Please convert the image to JPEG or PNG and try again.';
  }
}

class PreparedImageUpload {
  const PreparedImageUpload({
    required this.imageId,
    required this.existingImage,
    required this.uploadRequired,
    this.storagePath,
    this.uploadToken,
    this.thumbnailStoragePath,
    this.thumbnailUploadToken,
  });

  final String imageId;
  final bool existingImage;
  final bool uploadRequired;
  final String? storagePath;
  final String? uploadToken;
  final String? thumbnailStoragePath;
  final String? thumbnailUploadToken;

  bool get canSkipUpload => existingImage && !uploadRequired;

  factory PreparedImageUpload.fromResponse(dynamic data) {
    if (data is! Map) {
      throw StateError(
        'prepare-image-upload returned an unexpected response: $data',
      );
    }

    final imageId = data['image_id'];
    if (imageId is! String || imageId.trim().isEmpty) {
      throw StateError(
        'prepare-image-upload did not return a valid image ID. Response: $data',
      );
    }

    final existingImage = data['existing_image'] == true;
    final uploadRequired = data['upload_required'] == true;

    if (!uploadRequired && !existingImage) {
      throw StateError(
        'prepare-image-upload returned an inconsistent response. '
        'Response: $data',
      );
    }

    if (!uploadRequired) {
      return PreparedImageUpload(
        imageId: imageId.trim(),
        existingImage: true,
        uploadRequired: false,
      );
    }

    final storagePath = data['storage_path'];
    final uploadToken = data['upload_token'];
    final thumbnailStoragePath = data['thumbnail_storage_path'];
    final thumbnailUploadToken = data['thumbnail_upload_token'];
    if (storagePath is! String || storagePath.trim().isEmpty) {
      throw StateError(
        'prepare-image-upload did not return a valid Storage path. '
        'Response: $data',
      );
    }
    if (uploadToken is! String || uploadToken.trim().isEmpty) {
      throw StateError(
        'prepare-image-upload did not return a valid upload token. '
        'Response: $data',
      );
    }
    if (thumbnailStoragePath is! String || thumbnailStoragePath.trim().isEmpty) {
      throw StateError(
        'prepare-image-upload did not return a valid thumbnail Storage path. '
        'Response: $data',
      );
    }
    if (thumbnailUploadToken is! String || thumbnailUploadToken.trim().isEmpty) {
      throw StateError(
        'prepare-image-upload did not return a valid thumbnail upload token. '
        'Response: $data',
      );
    }

    return PreparedImageUpload(
      imageId: imageId.trim(),
      existingImage: existingImage,
      uploadRequired: true,
      storagePath: storagePath.trim(),
      uploadToken: uploadToken.trim(),
      thumbnailStoragePath: thumbnailStoragePath.trim(),
      thumbnailUploadToken: thumbnailUploadToken.trim(),
    );
  }
}

class ImageAssetService {
  ImageAssetService(this._supabase);

  final SupabaseClient _supabase;

  static const String _bucketName = 'reference-images';

  Future<dynamic> _invokeListWithRetry(
    Future<dynamic> Function() operation,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 0 ? 350 : 900),
          );
        }
      }
    }
    throw lastError!;
  }

  String get _normalizedUserEmail {
    final email = _supabase.auth.currentUser?.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      throw StateError(
        'You must be signed in before accessing the image library.',
      );
    }

    return email;
  }

  String get _userId {
    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$_normalizedUserEmail',
    );
  }

  Future<String> uploadImage(
    Uint8List imageBytes,
    ReferenceCategory category, {
    String? originalOwnerName,
    String? originalFilename,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final id = await _uploadImage(
        imageBytes: imageBytes,
        category: category,
        originalOwnerName: originalOwnerName,
        originalFilename: originalFilename,
      );
      UserActivityLogger.instance.record(
        operation: 'image_upload',
        status: 'succeeded',
        targetType: 'image',
        targetId: id,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {
          'category': category.databaseCode,
          'bytes': imageBytes.lengthInBytes,
        },
      );
      return id;
    } catch (error) {
      final duplicate = isDuplicateRejection(error);

      UserActivityLogger.instance.record(
        operation: 'image_upload',
        status: duplicate ? 'cancelled' : 'failed',
        targetType: 'image',
        durationMs: stopwatch.elapsedMilliseconds,
        details: {
          'category': category.databaseCode,
          'bytes': imageBytes.lengthInBytes,
          if (duplicate) 'reason': 'duplicate',
        },
        error: error,
      );
      rethrow;
    }
  }

  /// Whether the upload was refused because the image is already stored.
  ///
  /// A duplicate is the check working, not an error — but it was recorded as a
  /// failure, and at fifteen of forty-five recorded failures it made the
  /// failure count describe something other than things going wrong. The
  /// status column allows four values, so this is filed as a cancellation with
  /// its reason rather than inventing a fifth.
  static bool isDuplicateRejection(Object error) =>
      error is FunctionException && error.status == 409;

  Future<String> uploadAssociatedImage(
    Uint8List imageBytes,
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

    final stopwatch = Stopwatch()..start();
    try {
      final id = await _uploadImage(
        imageBytes: imageBytes,
        parentImageId: normalizedParentImageId,
      );
      UserActivityLogger.instance.record(
        operation: 'associated_image_upload',
        status: 'succeeded',
        targetType: 'sketch',
        targetId: id,
        parentImageId: normalizedParentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {'bytes': imageBytes.lengthInBytes},
      );
      return id;
    } catch (error) {
      final duplicate = isDuplicateRejection(error);

      UserActivityLogger.instance.record(
        operation: 'associated_image_upload',
        status: duplicate ? 'cancelled' : 'failed',
        targetType: 'sketch',
        parentImageId: normalizedParentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {
          'bytes': imageBytes.lengthInBytes,
          if (duplicate) 'reason': 'duplicate',
        },
        error: error,
      );
      rethrow;
    }
  }

  Future<String> _uploadImage({
    required Uint8List imageBytes,
    ReferenceCategory? category,
    String? parentImageId,
    String? originalOwnerName,
    String? originalFilename,
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

      late final Uint8List normalizedImageBytes;
      try {
        normalizedImageBytes = await ImageImportService.normalizeForUpload(
          imageBytes,
        );
      } catch (error) {
        profiler.checkpoint('Image format conversion failed: $error');
        throw const UnsupportedImageFormatException();
      }

      if (!identical(normalizedImageBytes, imageBytes)) {
        profiler.checkpoint(
          'HEIC/HEIF image converted to JPEG; converted size: '
          '${(normalizedImageBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(2)} MB',
        );
      }

      profiler.checkpoint(
        'Upload method started; original size: '
        '${(imageBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      // Derivative generation only depends on the normalized bytes, so it
      // starts now and overlaps with the hash calculation and the
      // prepare-image-upload network call below instead of running after
      // them. A listener is attached immediately (rather than only once we
      // reach the `await` further down) so Dart doesn't report this future's
      // error as unhandled while it's sitting unobserved during the
      // hash/network work below; a second, independent listener (the later
      // `await`) still collects the real result or error.
      final derivativesFuture = ThumbnailService.createDerivatives(
        normalizedImageBytes,
      );
      unawaited(
        derivativesFuture.catchError(
          (_) => ImageDerivatives(
            thumbnailBytes: Uint8List(0),
            width: 0,
            height: 0,
          ),
        ),
      );

      final isHeif = ImageImportService.isHeif(imageBytes);
      profiler.checkpoint('EXIF source detected: ${isHeif ? 'HEIC' : 'non-HEIC'}');

      final Future<PhotoMetadataExtraction> photoMetadataFuture;
      if (isHeif) {
        // HEIC (the default iPhone capture format) stores EXIF as a
        // distinct metadata item in the container rather than inline the
        // way JPEG does, and the HEIC-to-JPEG conversion above discards it
        // (it only bakes in orientation). So for HEIC specifically, read
        // EXIF directly from the untouched original bytes instead — a
        // fast, decode-free container parse, not an image decode at all.
        photoMetadataFuture = Future(() {
          final rawExif = HeifExifReader.findExifPayload(imageBytes);
          return rawExif == null
              ? const PhotoMetadataExtraction()
              : PhotoMetadataService.extractFromRawExif(rawExif);
        });
      } else {
        // EXIF extraction requires decoding full pixel data (this package
        // has no lightweight header-only reader), so on native it
        // piggybacks on the thumbnail instead of paying for a second
        // full-resolution decode of a possibly multi-megapixel camera
        // photo — package:image clones EXIF onto resized copies and writes
        // it back out when re-encoding, so the thumbnail carries the same
        // metadata. Web's thumbnail path goes through an HTML canvas
        // instead, which strips EXIF on re-encode, so it still reads the
        // full image there.
        photoMetadataFuture = derivativesFuture.then(
          (derivatives) => PhotoMetadataService.extract(
            kIsWeb ? normalizedImageBytes : derivatives.thumbnailBytes,
          ),
          onError: (_) => const PhotoMetadataExtraction(),
        );
      }
      unawaited(
        photoMetadataFuture.catchError(
          (_) => const PhotoMetadataExtraction(),
        ),
      );

      final imageHash = await ImageHashService.calculateSha256(
        normalizedImageBytes,
      );

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

      final preparedUpload = PreparedImageUpload.fromResponse(
        prepareResponse.data,
      );
      final preparedImageId = preparedUpload.imageId;

      if (preparedUpload.canSkipUpload) {
        profiler.finish(
          isAssociatedImage
              ? 'Existing image linked to parent; physical upload skipped'
              : 'Existing image found; physical upload skipped',
        );

        return preparedImageId;
      }

      late final ImageDerivatives derivatives;
      try {
        derivatives = await derivativesFuture;
      } catch (error) {
        profiler.checkpoint('Derivative creation failed: $error');
        throw const UnsupportedImageFormatException();
      }
      final thumbnailBytes = derivatives.thumbnailBytes;
      profiler.checkpoint(
        'Thumbnail created; size: '
        '${(thumbnailBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB'
      );
      if (thumbnailBytes.isEmpty) {
        throw const UnsupportedImageFormatException();
      }

      final storagePath = preparedUpload.storagePath!;
      final uploadToken = preparedUpload.uploadToken!;
      final thumbnailStoragePath = preparedUpload.thumbnailStoragePath!;
      final thumbnailUploadToken = preparedUpload.thumbnailUploadToken!;

      await Future.wait([
        _supabase.storage
            .from(_bucketName)
            .uploadBinaryToSignedUrl(
              storagePath,
              uploadToken,
              normalizedImageBytes,
              FileOptions(
                cacheControl: '3600',
                contentType: detectContentType(normalizedImageBytes),
                upsert: false,
              ),
            ),
        _supabase.storage
            .from(_bucketName)
            .uploadBinaryToSignedUrl(
              thumbnailStoragePath,
              thumbnailUploadToken,
              thumbnailBytes,
              const FileOptions(
                cacheControl: '86400',
                contentType: 'image/jpeg',
                upsert: false,
              ),
            ),
      ]);

      profiler.checkpoint(
        'Original and thumbnail uploaded directly '
        'to Supabase Storage',
      );

      final photoMetadata = await photoMetadataFuture;
      profiler.checkpoint(
        'Photo metadata extraction result: '
        'captureTimestamp=${photoMetadata.captureTimestamp != null}, '
        'metadata=${photoMetadata.metadata != null}',
      );

      final imageWidth = derivatives.width > 0 ? derivatives.width : null;
      final imageHeight = derivatives.height > 0 ? derivatives.height : null;

      final finalizeResponse = await _supabase.functions.invoke(
        'finalize-image-upload',
        body: {
          'user_id': _userId,
          'user_email': _normalizedUserEmail,
          ...destinationBody,
          'image_hash': imageHash,
          'image_id': preparedImageId,
          'storage_path': storagePath,
          'thumbnail_storage_path': thumbnailStoragePath,
          'original_owner_name': ?originalOwnerName,
          'original_filename': ?originalFilename,
          'capture_timestamp': ?photoMetadata
              .captureTimestamp
              ?.toIso8601String(),
          'photo_metadata': ?photoMetadata.metadata?.toJson(),
          'width': ?imageWidth,
          'height': ?imageHeight,
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
              ? 'Existing image linked during finalization'
              : 'Existing image found during finalization',
        );

        return finalizedImageId;
      }

      // The bytes are already here, so the one download guaranteed to be
      // unnecessary is the one that fetches back what was just sent. On a slow
      // connection that fetch is also the likeliest to stall, leaving somebody
      // who has just uploaded a photograph looking at nothing.
      //
      // Deliberately not awaited: a cache that fails to write must not fail an
      // upload that succeeded.
      unawaited(
        AppImageCache.seed(
          key: AppImageCache.fullKey(finalizedImageId),
          url: storagePath,
          bytes: normalizedImageBytes,
        ),
      );

      profiler.finish();

      return finalizedImageId;
    } catch (error) {
      profiler.fail(error);
      rethrow;
    }
  }

  Future<List<String>> listImageCategoryCodes(String imageId) async {
    final normalizedImageId = imageId.trim();

    if (normalizedImageId.isEmpty) {
      throw ArgumentError.value(
        imageId,
        'imageId',
        'The image ID cannot be empty.',
      );
    }

    final response = await _supabase
        .from('image_categories')
        .select('category_code')
        .eq('image_id', normalizedImageId);

    return response
        .map((row) => row['category_code'])
        .whereType<String>()
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> moveImageToCategory({
    required String imageId,
    required ReferenceCategory fromCategory,
    required ReferenceCategory toCategory,
  }) async {
    final normalizedImageId = imageId.trim();

    if (normalizedImageId.isEmpty) {
      throw ArgumentError.value(
        imageId,
        'imageId',
        'The image ID cannot be empty.',
      );
    }

    if (fromCategory.databaseCode == toCategory.databaseCode) {
      throw ArgumentError(
        'The source and destination categories are the same.',
      );
    }

    final response = await _supabase.functions.invoke(
      'move-image-to-category',
      body: {
        'user_id': _userId,
        'image_id': normalizedImageId,
        'from_category': fromCategory.databaseCode,
        'to_category': toCategory.databaseCode,
      },
    );

    final data = response.data;

    if (data is! Map) {
      throw StateError(
        'move-image-to-category returned an unexpected response: $data',
      );
    }

    if (data['moved'] != true) {
      throw StateError(data['error']?.toString() ?? 'The image was not moved.');
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
    UserActivityLogger.instance.record(
      operation: 'sketch_remove',
      status: 'succeeded',
      targetType: 'sketch',
      targetId: normalizedChildImageId,
      parentImageId: normalizedParentImageId,
    );
  }

  /// How many images each category holds, in a single request.
  ///
  /// The home screen needs numbers, not pictures. Getting them by listing every
  /// category in full meant one request per category, each signing two storage
  /// URLs per image and returning the lot so the caller could take its length —
  /// which made refreshing take minutes on a library of any size.
  ///
  /// Keyed by database code, with My Art under [ImageCategoryCounts.myArt]
  /// because it is derived rather than a stored category.
  Future<ImageCategoryCounts> countImagesByCategory() async {
    final response = await _invokeListWithRetry(
      () => _supabase.functions.invoke(
        'count-images-by-category',
        method: HttpMethod.get,
        headers: {'x-user-id': _userId},
      ),
    );

    final data = response.data;

    if (data is! Map) {
      throw StateError(
        'count-images-by-category returned an unexpected response: $data',
      );
    }

    final raw = data['counts'];
    final counts = <String, int>{};

    if (raw is Map) {
      raw.forEach((key, value) {
        final count = value is int ? value : int.tryParse('$value');
        if (count != null) counts['$key'] = count;
      });
    }

    final artwork = data['finished_artwork_count'];
    final ids = data['image_ids'];

    return ImageCategoryCounts(
      byCategoryCode: counts,
      finishedArtwork: artwork is int
          ? artwork
          : int.tryParse('$artwork') ?? 0,
      // Left null unless the server actually sent a list. An absent field must
      // not read as "you own nothing", which would empty the cache.
      ownedImageIds: ids is List
          ? ids.map((id) => '$id').where((id) => id.isNotEmpty).toSet()
          : null,
    );
  }

  Future<List<ImageAssetInfo>> listImages(ReferenceCategory category) async {
    if (category.isMyArt) {
      return listFinishedArtworks();
    }
    final cacheBuster = DateTime.now().millisecondsSinceEpoch;

    final response = await _invokeListWithRetry(
      () => _supabase.functions.invoke(
        'list-images?refresh=$cacheBuster',
        method: HttpMethod.get,
        headers: {
          'x-user-id': _userId,
          'x-category-code': category.databaseCode,
        },
      ),
    );

    final data = response.data;

    if (data is! List) {
      throw StateError(
        'The list-images function returned '
        'an unexpected response: $data',
      );
    }

    return parseImageAssetList(data, responseName: 'list-images');
  }

  Future<List<ImageAssetInfo>> listFinishedArtworks() async {
    final cacheBuster = DateTime.now().millisecondsSinceEpoch;
    final response = await _invokeListWithRetry(
      () => _supabase.functions.invoke(
        'list-finished-artworks?refresh=$cacheBuster',
        method: HttpMethod.get,
        headers: {'x-user-id': _userId},
      ),
    );
    final data = response.data;
    if (data is! List) {
      throw StateError(
        'list-finished-artworks returned an unexpected response: $data',
      );
    }
    return parseImageAssetList(data, responseName: 'list-finished-artworks');
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

    final response = await _invokeListWithRetry(
      () => _supabase.functions.invoke(
        'list-associated-images?refresh=$cacheBuster',
        method: HttpMethod.get,
        headers: {
          'x-user-id': _userId,
          'x-parent-image-id': normalizedParentImageId,
        },
      ),
    );

    final data = response.data;

    if (data is! List) {
      throw StateError(
        'The list-associated-images function '
        'returned an unexpected response: $data',
      );
    }

    return parseImageAssetList(data, responseName: 'list-associated-images');
  }

  static List<ImageAssetInfo> parseImageAssetList(
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
        displayUrl: row['display_url'] as String?,
        parentImageId: row['parent_image_id'] as String?,
        parentImageUrl: row['parent_image_url'] as String?,
      );
    }).toList();
  }

  static String detectContentType(Uint8List imageBytes) {
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
