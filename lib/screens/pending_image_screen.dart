import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/offline_upload_queue.dart';
import '../services/image_import_service.dart';
import '../services/local_user_session.dart';
import 'reference_viewer_screen.dart';

class PendingImageScreen extends StatelessWidget {
  const PendingImageScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });
  final List<PendingImageUpload> items;
  final int initialIndex;
  @override
  Widget build(BuildContext context) => ReferenceViewerScreen(
    count: items.length,
    initialIndex: initialIndex,
    imageBuilder: (_, index) =>
        PendingFullImage(key: ValueKey(items[index].id), item: items[index]),
  );
}

class PendingFullImage extends StatefulWidget {
  const PendingFullImage({super.key, required this.item});
  final PendingImageUpload item;
  @override
  State<PendingFullImage> createState() => _PendingFullImageState();
}

class _PendingFullImageState extends State<PendingFullImage> {
  late final Future<Uint8List> _bytes = _load();
  Future<Uint8List> _load() async {
    if (LocalUserSession.effectiveUserId != widget.item.userId) {
      throw StateError('Sign in to view this image.');
    }
    return ImageImportService.normalizeForUpload(
      await OfflineUploadQueue.instance.originalBytes(widget.item),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Unable to open this local image. If it has finished uploading, reopen it from the library.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        );
      }
      if (!snapshot.hasData) return const CircularProgressIndicator();
      return Image.memory(snapshot.data!, fit: BoxFit.contain);
    },
  );
}
