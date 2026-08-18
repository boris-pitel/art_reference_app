import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_save_result.dart';

class ImageSaveService {
  const ImageSaveService._();

  /// Remembers the folder picked last time so repeated saves land in the same
  /// place without renavigating to it.
  static const _lastDirectoryKey = 'image_save_last_directory';

  /// Menu/tooltip wording for the save action, which differs by platform
  /// because desktop prompts for a destination and mobile does not.
  static String get actionLabel => _isDesktop ? 'Save as…' : 'Save to Photos';

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<ImageSaveResult> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (_isDesktop) {
      return _saveToChosenFile(bytes, fileName: fileName);
    }

    return _saveToGallery(bytes);
  }

  static Future<ImageSaveResult> _saveToChosenFile(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    final location = await getSaveLocation(
      suggestedName: fileName,
      initialDirectory: await _lastDirectory(preferences),
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Images',
          extensions: [_extensionOf(fileName)],
        ),
      ],
    );

    if (location == null) {
      return const ImageSaveResult.cancelled();
    }

    final file = File(location.path);

    await file.writeAsBytes(bytes);

    await preferences.setString(_lastDirectoryKey, file.parent.path);

    return ImageSaveResult.savedToFile(file.path);
  }

  /// The last folder used, or null if it was never set or has since been
  /// removed — passing a stale directory to the dialog would strand the user
  /// somewhere that no longer exists.
  static Future<String?> _lastDirectory(SharedPreferences preferences) async {
    final directory = preferences.getString(_lastDirectoryKey);

    if (directory == null || directory.isEmpty) {
      return null;
    }

    if (!await Directory(directory).exists()) {
      return null;
    }

    return directory;
  }

  static String _extensionOf(String fileName) {
    final separatorIndex = fileName.lastIndexOf('.');

    if (separatorIndex < 0 || separatorIndex == fileName.length - 1) {
      return 'jpg';
    }

    return fileName.substring(separatorIndex + 1).toLowerCase();
  }

  static Future<ImageSaveResult> _saveToGallery(Uint8List bytes) async {
    var hasAccess = await Gal.hasAccess();

    if (!hasAccess) {
      hasAccess = await Gal.requestAccess();
    }

    if (!hasAccess) {
      throw StateError('Permission to save images was not granted.');
    }

    await Gal.putImageBytes(bytes);

    return const ImageSaveResult.savedToGallery();
  }
}
