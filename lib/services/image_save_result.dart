/// Where an image ended up when [ImageSaveService.save] finished.
class ImageSaveResult {
  const ImageSaveResult._(this.path, this.wasCancelled);

  /// Written to a specific file the user chose. [path] is that file.
  const ImageSaveResult.savedToFile(String path) : this._(path, false);

  /// Handed to the system photo gallery, which does not expose a path.
  const ImageSaveResult.savedToGallery() : this._(null, false);

  /// Handed to the browser as a download; the destination is not visible to us.
  const ImageSaveResult.downloaded() : this._(null, false);

  /// The user dismissed the save dialog. Nothing was written.
  const ImageSaveResult.cancelled() : this._(null, true);

  /// The file that was written, when a concrete destination is known.
  final String? path;

  /// True when the user backed out and no bytes were written.
  final bool wasCancelled;
}
