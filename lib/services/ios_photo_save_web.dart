// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Presents an image for saving with Safari's own press-and-hold gesture.
///
/// Handing the file to the share sheet and choosing "Save Image" does nothing
/// on iOS — Photos accepts the identical bytes when they arrive as an ordinary
/// image on a page, and refuses them when they arrive as a shared file. Rather
/// than fight that, this puts the image on the page as a real element, where
/// press-and-hold offers "Add to Photos" exactly as it does on any website.
///
/// The element has to be genuine DOM: Flutter draws to a canvas, and Safari
/// offers nothing for pressing and holding on a canvas.
class IosPhotoSave {
  const IosPhotoSave._();

  static const _overlayId = '__painter_reference_save_overlay__';

  /// Shows the image full-width with instructions, until dismissed.
  static Future<void> present(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    dismiss();

    final blob = html.Blob(<Object>[bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final overlay = html.DivElement()
      ..id = _overlayId
      ..style.cssText =
          'position:fixed;inset:0;z-index:2147483647;background:rgba(12,10,18,.94);'
          'display:flex;flex-direction:column;align-items:center;justify-content:center;'
          'gap:18px;padding:24px;box-sizing:border-box;'
          'font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;';

    final instructions = html.ParagraphElement()
      ..text = 'Press and hold the image, then choose "Add to Photos".'
      ..style.cssText =
          'color:#fff;font-size:16px;line-height:1.45;text-align:center;margin:0;'
          'max-width:32ch;';

    final image = html.ImageElement(src: url)
      ..style.cssText =
          'max-width:100%;max-height:62vh;object-fit:contain;border-radius:8px;'
          // -webkit-touch-callout must stay enabled or iOS suppresses the very
          // menu this exists to offer.
          '-webkit-touch-callout:default;-webkit-user-select:auto;user-select:auto;';

    final done = html.ButtonElement()
      ..text = 'Done'
      ..style.cssText =
          'appearance:none;border:none;border-radius:999px;padding:12px 30px;'
          'font-size:16px;font-weight:600;color:#191524;background:#fff;'
          'cursor:pointer;';

    final closed = Completer<void>();

    done.onClick.listen((_) {
      if (!closed.isCompleted) closed.complete();
    });

    overlay.append(instructions);
    overlay.append(image);
    overlay.append(done);
    html.document.body!.append(overlay);

    await closed.future;

    dismiss();

    // Deferred: revoking while Photos is still reading the image would cancel
    // a save the user has already started.
    Timer(
      const Duration(minutes: 2),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  static void dismiss() {
    html.document.getElementById(_overlayId)?.remove();
  }
}
