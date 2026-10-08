import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:typed_data';
import '../models/reference_document.dart';

class DocumentDelivery {
  static Future<void> open(ReferenceDocument doc, Uint8List bytes) =>
      save(doc, bytes);
  static Future<void> save(ReferenceDocument doc, Uint8List bytes) async {
    final url = web.URL.createObjectURL(
      web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(
          type:
              DocumentFormat.mimeTypes[doc.fileType] ??
              'application/octet-stream',
        ),
      ),
    );
    final anchor = (web.document.createElement('a') as web.HTMLAnchorElement)
      ..href = url
      ..download = doc.filename
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    Future.delayed(const Duration(minutes: 1), () {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    });
  }
}
