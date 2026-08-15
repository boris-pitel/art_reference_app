// Manual stress/benchmark run for the upload and download paths. Not part
// of the regular pass/fail e2e suite: it reports timing statistics to the
// console rather than asserting on latency, since network timing is
// inherently variable and shouldn't make a test flaky. Run it directly with:
//   flutter test integration_test/upload_download_stress_test.dart -d windows
import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_support.dart';

const _sequentialUploadCount = 15;
const _concurrentUploadCount = 5;
const _concurrentDownloadCount = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ReferenceCategory> inboxCategory(SupabaseClient client) async {
    final categories = await CategoryService(client).listCategories();
    return categories.firstWhere((category) => category.isInbox);
  }

  testWidgets('stress: repeated uploads and downloads, report timing stats', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final inbox = await inboxCategory(session.client);

    // --- Sequential uploads: what one person uploading one at a time sees.
    final sequentialUploadMs = <int>[];
    for (var i = 0; i < _sequentialUploadCount; i++) {
      final stopwatch = Stopwatch()..start();
      await assets.uploadImage(uniqueImageBytes(seed: i), inbox);
      stopwatch.stop();
      sequentialUploadMs.add(stopwatch.elapsedMilliseconds);
    }
    _report('UPLOAD sequential (n=$_sequentialUploadCount)', sequentialUploadMs);

    // --- Concurrent burst: reveals contention on the single-connection
    // Edge Function DB pools documented in docs/network-performance-analysis.md.
    final concurrentBurstStopwatch = Stopwatch()..start();
    final concurrentUploadMs = await Future.wait(
      List.generate(_concurrentUploadCount, (i) async {
        final stopwatch = Stopwatch()..start();
        await assets.uploadImage(uniqueImageBytes(seed: 1000 + i), inbox);
        stopwatch.stop();
        return stopwatch.elapsedMilliseconds;
      }),
    );
    concurrentBurstStopwatch.stop();
    _report(
      'UPLOAD concurrent (n=$_concurrentUploadCount, '
      'batch wall time=${concurrentBurstStopwatch.elapsedMilliseconds}ms)',
      concurrentUploadMs,
    );

    // --- Downloads: fetch the listing once, then time raw GETs against the
    // signed Storage URLs the app actually displays (same as Image.network).
    final images = await assets.listImages(inbox);
    expect(images.length, greaterThanOrEqualTo(_sequentialUploadCount));

    final sequentialOriginalMs = <int>[];
    final sequentialThumbnailMs = <int>[];
    for (final image in images.take(_sequentialUploadCount)) {
      final originalStopwatch = Stopwatch()..start();
      final originalResponse = await http.get(Uri.parse(image.imageUrl));
      originalStopwatch.stop();
      expect(originalResponse.statusCode, 200);
      sequentialOriginalMs.add(originalStopwatch.elapsedMilliseconds);

      final thumbnailUrl = image.thumbnailUrl;
      if (thumbnailUrl != null) {
        final thumbnailStopwatch = Stopwatch()..start();
        final thumbnailResponse = await http.get(Uri.parse(thumbnailUrl));
        thumbnailStopwatch.stop();
        expect(thumbnailResponse.statusCode, 200);
        sequentialThumbnailMs.add(thumbnailStopwatch.elapsedMilliseconds);
      }
    }
    _report('DOWNLOAD original sequential', sequentialOriginalMs);
    _report('DOWNLOAD thumbnail sequential', sequentialThumbnailMs);

    final downloadTargets = images.take(_concurrentDownloadCount).toList();
    final concurrentDownloadStopwatch = Stopwatch()..start();
    final concurrentDownloadMs = await Future.wait(
      downloadTargets.map((image) async {
        final stopwatch = Stopwatch()..start();
        final response = await http.get(Uri.parse(image.imageUrl));
        stopwatch.stop();
        expect(response.statusCode, 200);
        return stopwatch.elapsedMilliseconds;
      }),
    );
    concurrentDownloadStopwatch.stop();
    _report(
      'DOWNLOAD original concurrent (n=${downloadTargets.length}, '
      'batch wall time=${concurrentDownloadStopwatch.elapsedMilliseconds}ms)',
      concurrentDownloadMs,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void _report(String label, List<int> durationsMs) {
  if (durationsMs.isEmpty) {
    // ignore: avoid_print
    print('[$label] no samples');
    return;
  }
  final sorted = [...durationsMs]..sort();
  final sum = sorted.reduce((a, b) => a + b);
  final average = sum / sorted.length;
  final median = sorted[sorted.length ~/ 2];
  final p95Index = ((sorted.length * 0.95).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  // ignore: avoid_print
  print(
    '[$label] n=${sorted.length} '
    'avg=${average.toStringAsFixed(0)}ms '
    'median=${median}ms '
    'min=${sorted.first}ms '
    'max=${sorted.last}ms '
    'p95=${sorted[p95Index]}ms',
  );
}
