import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final width = 6000;
  final height = 8000;

  print('Generating synthetic test image: $width×$height...');

  // Create a simple gradient image
  final image = img.Image(width: width, height: height);

  // Fill with a gradient pattern (vertical stripes for easy visual verification)
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final r = (x * 255 ~/ width);
      final g = (y * 255 ~/ height);
      final b = ((x + y) * 128 ~/ (width + height));
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Encode as JPEG at high quality
  final jpegBytes = img.encodeJpg(image, quality: 95);

  final outputFile = File('test_image_6000x8000.jpg');
  outputFile.writeAsBytesSync(jpegBytes);

  print('✓ Test image created: ${outputFile.path}');
  print('  Resolution: $width×$height');
  print('  Size: ${(jpegBytes.length / 1024 / 1024).toStringAsFixed(1)} MB');
  print('');
  print('To test:');
  print('1. Open the Art Reference App (Windows)');
  print('2. Upload this test image');
  print('3. View it (should use display tier, no blank screen)');
  print('4. Edit and save to disk');
  print('5. Check saved file resolution (should be 6000×8000)');
}
