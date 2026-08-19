import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/gesture_share.dart';
import '../services/image_dimensions_reader.dart';
import '../services/image_print_service.dart';
import '../services/image_save_service.dart';
import '../services/web_print.dart';

/// Routes saving and printing to whichever mechanism the platform supports.
///
/// Everywhere except iOS this is a straight pass-through. On iOS the browser
/// will not open a print dialog at all, and will only share a file from inside
/// a live user gesture — which the image download has already spent by the time
/// these are called. So iOS gets a confirmation step whose tap is a fresh
/// gesture, and the share happens synchronously inside it.
class ImageDelivery {
  const ImageDelivery._();

  /// iOS already reaches a printer through the share sheet, so only Android
  /// browsers need the page-printing route.
  static bool get _androidWebPrinting =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<ImageSaveResult> save(
    BuildContext context,
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (!GestureShare.isRequired) {
      return ImageSaveService.save(bytes, fileName: fileName);
    }

    final shared = await _confirmHandoff(
      context,
      title: 'Save image',
      // The destination app differs by platform, and a browser download cannot
      // reach the photo library on either — the share sheet is the only route.
      body: GestureShare.isIosBrowser
          ? 'Your image is ready. Choose "Save Image" in the share sheet to '
                'add it to Photos.'
          : 'Your image is ready. Choose Photos or Gallery in the share sheet '
                'to add it there.',
      actionLabel: 'Continue',
      bytes: bytes,
      fileName: fileName,
      mimeType: fileName.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg',
    );

    return shared
        ? const ImageSaveResult.downloaded()
        : const ImageSaveResult.cancelled();
  }

  static Future<void> printImage(
    BuildContext context,
    Uint8List imageBytes, {
    required String documentName,
  }) async {
    // Android browsers get the print dialog directly. The printing package
    // will not attempt one for a mobile user agent — it downloads a PDF and
    // offers an app chooser instead, which never reaches a printer.
    if (_androidWebPrinting) {
      final printed = await WebPrint.printImage(
        imageBytes,
        mimeType: imageBytes.length >= 8 &&
                imageBytes[1] == 0x50 &&
                imageBytes[2] == 0x4e
            ? 'image/png'
            : 'image/jpeg',
      );

      if (printed || !context.mounted) return;

      // Most likely the browser refused to decode a very large photo.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This image is too large for your browser to print. Save it and '
            'print from another app.',
          ),
        ),
      );
      return;
    }

    if (!GestureShare.isRequired) {
      return ImagePrintService.printImage(
        imageBytes: imageBytes,
        documentName: documentName,
      );
    }

    final pdfBytes = await ImagePrintService.buildPdf(imageBytes: imageBytes);

    if (!context.mounted) return;

    await _confirmHandoff(
      context,
      title: 'Print image',
      body: 'Your document is ready. Choose "Print" in the share sheet to send '
          'it to a printer.',
      actionLabel: 'Continue',
      bytes: pdfBytes,
      fileName: '$documentName.pdf',
      mimeType: 'application/pdf',
    );
  }

  /// Shows the confirmation and performs the share from its callback.
  ///
  /// The share call must not be preceded by an `await` inside the callback, or
  /// Safari will have dropped the user activation again by the time it runs.
  static Future<bool> _confirmHandoff(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final tooLargeForPhotos = _exceedsPhotosLimit(bytes, mimeType);

    final shared = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              if (tooLargeForPhotos != null) ...[
                const SizedBox(height: 14),
                Text(
                  tooLargeForPhotos,
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                GestureShare.shareBytes(
                  bytes,
                  fileName: fileName,
                  mimeType: mimeType,
                );
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    return shared ?? false;
  }

  /// iOS decodes a JPEG only up to roughly 32 megapixels, and importing to
  /// Photos requires a decode — so above that the share sheet accepts the file
  /// and Photos silently discards it. Documented in Apple's Safari Web Content
  /// Guide and confirmed here: a 6000x8000 (48MP) photo never reached Photos,
  /// while the same file uploaded to a cloud app intact, because an upload
  /// copies bytes without decoding them.
  ///
  /// Whether newer hardware raises the ceiling is unconfirmed. Warning when a
  /// save would have worked is a far smaller cost than staying silent when it
  /// will not, so the documented figure stands until measured otherwise.
  static const _photosMegapixelLimit = 32;

  /// The warning to show, or null when the image is safely within the limit.
  ///
  /// The failure itself cannot be detected: iOS reports nothing back once the
  /// share sheet takes the file, so this predicts rather than reacts.
  static String? _exceedsPhotosLimit(Uint8List bytes, String mimeType) {
    if (!mimeType.startsWith('image/')) return null;

    // The limit and the wording are both iOS-specific. Android's gallery has
    // its own behaviour, unmeasured here, and claiming an iPhone limit on an
    // Android phone would be worse than saying nothing.
    if (!GestureShare.isIosBrowser) return null;

    final dimensions = ImageDimensionsReader.read(bytes);
    if (dimensions == null) return null;

    final megapixels = dimensions.megapixels;
    if (megapixels <= _photosMegapixelLimit) return null;

    return 'This image is $megapixels megapixels. iPhone cannot add images '
        'above about $_photosMegapixelLimit megapixels to Photos — use AirDrop, '
        'Mail, or a cloud app instead.';
  }
}
