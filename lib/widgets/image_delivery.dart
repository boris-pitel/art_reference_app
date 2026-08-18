import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/gesture_share.dart';
import '../services/image_print_service.dart';
import '../services/image_save_service.dart';

/// Routes saving and printing to whichever mechanism the platform supports.
///
/// Everywhere except iOS this is a straight pass-through. On iOS the browser
/// will not open a print dialog at all, and will only share a file from inside
/// a live user gesture — which the image download has already spent by the time
/// these are called. So iOS gets a confirmation step whose tap is a fresh
/// gesture, and the share happens synchronously inside it.
class ImageDelivery {
  const ImageDelivery._();

  /// Whether a Print control is worth offering.
  ///
  /// Mobile browsers cannot reach a print dialog: the printing package checks
  /// for a mobile user agent and skips that path entirely, and its fallback of
  /// opening the PDF in a new tab is blocked without user activation, which the
  /// image download has already spent. The result is a control that appears to
  /// work and does nothing, so it is hidden rather than shown broken. Sharing
  /// and downloading still reach a printer.
  static bool get printingIsAvailable {
    if (!kIsWeb) return true;

    return defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android;
  }

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
      body: 'Your image is ready. Choose "Save Image" in the share sheet to '
          'add it to Photos.',
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
    final shared = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
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
}
