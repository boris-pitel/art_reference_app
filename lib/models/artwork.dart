import 'image_asset.dart';

class Artwork {
  const Artwork({
    required this.id,
    required this.image,
    this.title,
    this.notes,
  });

  final String id;
  final ImageAsset image;

  final String? title;
  final String? notes;
}
