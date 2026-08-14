import 'dart:typed_data';

import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreparedImageUpload', () {
    test('recognizes a deduplicated image that skips physical upload', () {
      final prepared = PreparedImageUpload.fromResponse({
        'image_id': ' existing-id ',
        'existing_image': true,
        'upload_required': false,
      });

      expect(prepared.imageId, 'existing-id');
      expect(prepared.canSkipUpload, isTrue);
      expect(prepared.storagePath, isNull);
      expect(prepared.uploadToken, isNull);
    });

    test('requires a signed path and token for a new upload', () {
      final prepared = PreparedImageUpload.fromResponse({
        'image_id': 'new-id',
        'existing_image': false,
        'upload_required': true,
        'storage_path': ' owner/originals/new-id ',
        'upload_token': ' signed-token ',
        'thumbnail_storage_path': ' owner/thumbnails/new-id.jpg ',
        'thumbnail_upload_token': ' signed-thumbnail-token ',
      });

      expect(prepared.canSkipUpload, isFalse);
      expect(prepared.storagePath, 'owner/originals/new-id');
      expect(prepared.uploadToken, 'signed-token');
      expect(prepared.thumbnailStoragePath, 'owner/thumbnails/new-id.jpg');
      expect(prepared.thumbnailUploadToken, 'signed-thumbnail-token');
    });

    test('rejects a new upload response missing thumbnail signing info', () {
      expect(
        () => PreparedImageUpload.fromResponse({
          'image_id': 'new-id',
          'existing_image': false,
          'upload_required': true,
          'storage_path': 'owner/originals/new-id',
          'upload_token': 'signed-token',
        }),
        throwsStateError,
      );
    });

    test('rejects inconsistent and incomplete prepare responses', () {
      expect(
        () => PreparedImageUpload.fromResponse({
          'image_id': 'new-id',
          'existing_image': false,
          'upload_required': false,
        }),
        throwsStateError,
      );
      expect(
        () => PreparedImageUpload.fromResponse({
          'image_id': 'new-id',
          'upload_required': true,
          'storage_path': 'path',
        }),
        throwsStateError,
      );
      expect(
        () => PreparedImageUpload.fromResponse({'upload_required': true}),
        throwsStateError,
      );
      expect(
        () => PreparedImageUpload.fromResponse('not a map'),
        throwsStateError,
      );
    });
  });

  group('ImageAssetService.parseImageAssetList', () {
    test('parses a complete image row', () {
      final result = ImageAssetService.parseImageAssetList([
        {
          'id': 'image-id',
          'date_added': '2026-08-12T10:30:00Z',
          'image_url': 'https://example.test/image',
          'thumbnail_url': 'https://example.test/thumb',
          'parent_image_id': 'parent-id',
          'parent_image_url': 'https://example.test/parent',
        },
      ], responseName: 'test-list');

      expect(result, hasLength(1));
      expect(result.single.id, 'image-id');
      expect(result.single.dateAdded.isUtc, isTrue);
      expect(result.single.thumbnailUrl, contains('/thumb'));
      expect(result.single.parentImageId, 'parent-id');
    });

    test('rejects malformed rows instead of leaking partial data', () {
      for (final row in [
        'not a map',
        {'id': '', 'date_added': '2026-08-12T10:30:00Z', 'image_url': 'url'},
        {'id': 'id', 'date_added': 'not-a-date', 'image_url': 'url'},
        {'id': 'id', 'date_added': '2026-08-12T10:30:00Z', 'image_url': ''},
      ]) {
        expect(
          () => ImageAssetService.parseImageAssetList([
            row,
          ], responseName: 'test-list'),
          throwsStateError,
          reason: '$row',
        );
      }
    });
  });

  group('ImageAssetService.detectContentType', () {
    test('detects JPEG and PNG signatures', () {
      expect(
        ImageAssetService.detectContentType(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
        ),
        'image/jpeg',
      );
      expect(
        ImageAssetService.detectContentType(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        ),
        'image/png',
      );
    });

    test('falls back safely for unknown or truncated data', () {
      expect(
        ImageAssetService.detectContentType(Uint8List.fromList([1, 2])),
        'application/octet-stream',
      );
    });
  });
}
