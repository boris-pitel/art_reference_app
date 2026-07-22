class ImageAsset {
  const ImageAsset({
    required this.id,
    required this.dateAdded,
    this.width,
    this.height,
  });

  final String id;
  final DateTime dateAdded;

  final int? width;
  final int? height;
}
