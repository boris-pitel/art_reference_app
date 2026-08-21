import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/gesture_share.dart';
import '../services/image_dimensions_reader.dart';
import '../services/ios_photo_save.dart';
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

  /// Whether Share and Save are the same action on this platform.
  ///
  /// True only on Android browsers, where a download cannot reach the gallery
  /// so saving goes through the share sheet — exactly what sharing already did,
  /// leaving two menu items that open the identical sheet. iOS saves through
  /// press-and-hold instead, so the two are distinct there again; desktop web
  /// downloads; and the native apps write to Photos or a chosen folder.
  static bool get shareAndSaveAreIdentical =>
      GestureShare.isRequired && !GestureShare.isIosBrowser;

  static Future<ImageSaveResult> save(
    BuildContext context,
    Uint8List bytes, {
    required String fileName,
  }) async {
    // iOS Photos refuses a file handed over by the share sheet while accepting
    // the identical bytes shown as an image on a page, so saving there uses
    // press-and-hold instead — the gesture that demonstrably works.
    if (GestureShare.isIosBrowser) {
      await IosPhotoSave.present(
        bytes,
        mimeType: fileName.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg',
      );

      // Whether the user completed the save is not observable, and the
      // instructions are on screen throughout, so nothing further is claimed.
      return const ImageSaveResult.downloaded();
    }

    if (!GestureShare.isRequired) {
      return ImageSaveService.save(bytes, fileName: fileName);
    }

    final shared = await _confirmHandoff(
      context,
      title: 'Save image',
      // The destination app differs by platform, and a browser download cannot
      // reach the photo library on either — the share sheet is the only route.
      body: _shareInstructions(bytes),
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

  /// Above this, a photo library is liable to reject the image without saying
  /// so, on either platform.
  ///
  /// iOS decodes a JPEG only to about this size and importing to Photos
  /// requires a decode, which is documented in Apple's Safari Web Content
  /// Guide. Android has no published figure; all that is established is that a
  /// 6000x8000 (48MP) photo reached Google Photos, showed an upload progress
  /// bar, and never appeared — while the same file saved through Files intact.
  /// The Apple number is therefore used for both as a conservative estimate,
  /// not as a measured Android limit.
  ///
  /// Both failures are silent: once the share sheet accepts a file, neither
  /// platform reports back what the destination did with it. So this steers
  /// the user beforehand rather than reacting afterwards, and pointing someone
  /// at Files when Photos would have coped costs far less than the reverse.
  static const _photosMegapixelLimit = 32;

  /// What to tell the user before the share sheet opens, given what the photo
  /// libraries will and will not accept.
  static String _shareInstructions(Uint8List bytes) {
    final dimensions = ImageDimensionsReader.read(bytes);
    final megapixels = dimensions?.megapixels;

    if (megapixels != null && megapixels > _photosMegapixelLimit) {
      // Photos and Files both fail silently at this size, while a cloud app
      // succeeds — confirmed on both platforms. The difference is that an
      // upload copies bytes, where saving to the phone decodes the image, and
      // that decode is what a photo this large exceeds.
      return 'This photo is $megapixels megapixels — too large for your phone '
          'to save. Send it to a cloud app such as Drive, or email it to '
          'yourself. Saving to Photos or Files will appear to work and will '
          'not.';
    }

    return GestureShare.isIosBrowser
        ? 'Your image is ready. Choose "Save Image" in the share sheet to add '
              'it to Photos.'
        : 'Your image is ready. Choose Photos or Gallery to add it there, or '
              'Files to save it to your phone.';
  }

}
