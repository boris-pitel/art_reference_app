import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ImagePrintService {
  const ImagePrintService._();

  static Future<void> printImage({
    required Uint8List imageBytes,
    required String documentName,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(
        imageBytes,
        'imageBytes',
        'The image is empty.',
      );
    }

    final image = pw.MemoryImage(imageBytes);

    await Printing.layoutPdf(
      name: documentName,
      onLayout: (PdfPageFormat pageFormat) async {
        final document = pw.Document();

        document.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(18),
            build: (context) {
              return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
            },
          ),
        );

        return document.save();
      },
    );
  }
}
