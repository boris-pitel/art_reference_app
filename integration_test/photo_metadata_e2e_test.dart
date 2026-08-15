import 'dart:typed_data';

import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ReferenceCategory> inboxCategory(SupabaseClient client) async {
    final categories = await CategoryService(client).listCategories();
    return categories.firstWhere((category) => category.isInbox);
  }

  testWidgets(
    'uploads capture timestamp, filename, and camera/exposure EXIF fields',
    (tester) async {
      final session = await createTestSession(tester);
      final assets = ImageAssetService(session.client);
      final inbox = await inboxCategory(session.client);

      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(120, 90, 60));
      image.exif.imageIfd.make = 'Fujifilm';
      image.exif.imageIfd.model = 'X-T5';
      image.exif.exifIfd[0x9003] = img.IfdValueAscii('2025:03:10 09:15:00');
      image.exif.exifIfd[0x829D] = img.IfdValueRational(56, 10);
      image.exif.exifIfd[0x829A] = img.IfdValueRational(1, 250);
      image.exif.exifIfd[0x8827] = img.IfdValueLong(200);
      image.exif.exifIfd[0x920A] = img.IfdValueRational(35, 1);
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 92));

      final imageId = await assets.uploadImage(
        bytes,
        inbox,
        originalFilename: 'DSCF1234.JPG',
      );

      final metadata = await fetchImageMetadata(
        session.client,
        session.dataUserId,
        imageId,
      );

      expect(metadata['original_filename'], 'DSCF1234.JPG');
      expect(metadata['capture_timestamp'], isNotNull);
      expect(
        DateTime.parse(metadata['capture_timestamp'] as String),
        DateTime.utc(2025, 3, 10, 9, 15, 0),
      );

      final photoMetadata = metadata['photo_metadata'] as Map;
      expect(photoMetadata['camera_make'], 'Fujifilm');
      expect(photoMetadata['camera_model'], 'X-T5');
      expect((photoMetadata['aperture'] as num).toDouble(), closeTo(5.6, 0.01));
      expect(photoMetadata['shutter_speed'], '1/250s');
      expect(photoMetadata['iso'], 200);
      expect((photoMetadata['focal_length_mm'] as num).toDouble(), 35.0);
    },
  );

  testWidgets('uploads without EXIF leave the photo detail fields null', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final inbox = await inboxCategory(session.client);

    final imageId = await assets.uploadImage(uniqueImageBytes(seed: 7), inbox);

    final metadata = await fetchImageMetadata(
      session.client,
      session.dataUserId,
      imageId,
    );

    expect(metadata['original_filename'], isNull);
    expect(metadata['capture_timestamp'], isNull);
    expect(metadata['photo_metadata'], isNull);
  });
}
