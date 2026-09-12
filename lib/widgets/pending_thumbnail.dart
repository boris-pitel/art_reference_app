import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/offline_upload_queue.dart';
import '../services/image_import_service.dart';
import '../services/thumbnail_service.dart';

class PendingThumbnail extends StatefulWidget {
  const PendingThumbnail({super.key, required this.item, this.queue});
  final PendingImageUpload item;
  final OfflineUploadQueue? queue;
  @override
  State<PendingThumbnail> createState() => _PendingThumbnailState();
}

class _PendingThumbnailState extends State<PendingThumbnail> {
  late final Future<Uint8List> _bytes = _load();
  Future<Uint8List> _load() async {
    if (widget.item.previewBytes.isNotEmpty) return widget.item.previewBytes;
    final original = await (widget.queue ?? OfflineUploadQueue.instance)
        .originalBytes(widget.item);
    final normalized = await ImageImportService.normalizeForUpload(original);
    return (await ThumbnailService.createDerivatives(
      normalized,
    )).thumbnailBytes;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      }
      return Center(
        child: snapshot.hasError
            ? const Icon(Icons.image_outlined)
            : const CircularProgressIndicator(strokeWidth: 2),
      );
    },
  );
}
