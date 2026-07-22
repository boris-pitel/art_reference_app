import 'image_asset.dart';
import 'reference_category.dart';

class PhotoReference {
  const PhotoReference({
    required this.id,
    required this.image,
    required this.category,
    this.keywords = const [],
    this.notes,
    this.relatedArtworkIds = const [],
  });

  final String id;
  final ImageAsset image;
  final ReferenceCategory category;

  final List<String> keywords;
  final String? notes;

  final List<String> relatedArtworkIds;
}
