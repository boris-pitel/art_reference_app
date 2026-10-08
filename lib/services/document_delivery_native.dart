import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/reference_document.dart';

class DocumentDelivery {
  static Future<void> open(ReferenceDocument doc, Uint8List bytes) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/reference_documents',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${doc.id}.${doc.fileType}');
    await file.writeAsBytes(bytes, flush: true);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (!await launchUrl(file.uri)) {
        throw StateError(
          'No application could open this document. Save it and open it from your files.',
        );
      }
    } else {
      final result = await OpenFilex.open(
        file.path,
        type: DocumentFormat.mimeTypes[doc.fileType],
      );
      if (result.type != ResultType.done) throw StateError(result.message);
    }
  }

  static Future<void> save(ReferenceDocument doc, Uint8List bytes) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: DocumentFormat.mimeTypes[doc.fileType],
            ),
          ],
          fileNameOverrides: [doc.filename],
        ),
      );
      return;
    }
    final destination = await getSaveLocation(suggestedName: doc.filename);
    if (destination != null) await File(destination.path).writeAsBytes(bytes);
  }
}
