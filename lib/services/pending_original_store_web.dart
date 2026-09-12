import 'dart:typed_data';

Future<void> savePendingOriginal(
  String id,
  Uint8List bytes, {
  String? directoryPath,
}) async => throw UnsupportedError('Use IndexedDB');
Future<Uint8List> readPendingOriginal(
  String id, {
  String? directoryPath,
}) async => throw UnsupportedError('Use IndexedDB');
Future<void> deletePendingOriginal(String id, {String? directoryPath}) async {}

Future<void> releaseCapturedTemporaryFile(String path) async {}
