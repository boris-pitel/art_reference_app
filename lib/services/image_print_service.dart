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
    _assertNotEmpty(imageBytes);

    await Printing.layoutPdf(
      name: documentName,
      onLayout: (PdfPageFormat pageFormat) async =>
          _buildDocument(imageBytes, pageFormat),
    );
  }

  /// Builds the same document [printImage] would print, but returns it instead.
  ///
  /// Needed on iOS, where the browser never opens a print dialog and the PDF
  /// has to be handed to the system share sheet (which offers AirPrint) rather
  /// than printed directly.
  static Future<Uint8List> buildPdf({
    required Uint8List imageBytes,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    _assertNotEmpty(imageBytes);

    return _buildDocument(imageBytes, pageFormat);
  }

  static Future<Uint8List> _buildDocument(
    Uint8List imageBytes,
    PdfPageFormat pageFormat,
  ) async {
    final image = pw.MemoryImage(imageBytes);

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
  }

  static void _assertNotEmpty(Uint8List imageBytes) {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'The image is empty.');
    }
  }
}
