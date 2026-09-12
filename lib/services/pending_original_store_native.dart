import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<File> _file(String id, String? directoryPath) async {
  if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
    throw ArgumentError('Invalid image ID');
  }
  final root = directoryPath ?? (await getApplicationSupportDirectory()).path;
  final dir = Directory('$root/pending_originals');
  await dir.create(recursive: true);
  return File('${dir.path}/$id');
}

Future<void> savePendingOriginal(
  String id,
  Uint8List bytes, {
  String? directoryPath,
}) async {
  await (await _file(id, directoryPath)).writeAsBytes(bytes, flush: true);
}

Future<Uint8List> readPendingOriginal(
  String id, {
  String? directoryPath,
}) async => (await _file(id, directoryPath)).readAsBytes();
Future<void> deletePendingOriginal(String id, {String? directoryPath}) async {
  final file = await _file(id, directoryPath);
  if (await file.exists()) await file.delete();
}

/// Only remove the camera's temporary copy after durable queue storage succeeds.
Future<void> releaseCapturedTemporaryFile(String path) async {
  try {
    final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    final file = File(path);
    final resolved = await file.resolveSymbolicLinks();
    if (resolved.startsWith('$root${Platform.pathSeparator}')) {
      await file.delete();
    }
  } catch (_) {
    /* Temporary cleanup must never invalidate a saved capture. */
  }
}
