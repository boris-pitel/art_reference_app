import 'artwork.dart';
import 'photo_reference.dart';
import 'reference_category.dart';

class ReferenceLibrary {
  final List<PhotoReference> _photoReferences = [];
  final List<Artwork> _artworks = [];

  List<PhotoReference> get photoReferences =>
      List.unmodifiable(_photoReferences);

  List<Artwork> get artworks => List.unmodifiable(_artworks);

  void addPhotoReference(PhotoReference reference) {
    _photoReferences.add(reference);
  }

  void addArtwork(Artwork artwork) {
    _artworks.add(artwork);
  }

  List<PhotoReference> referencesForCategory(ReferenceCategory category) {
    return _photoReferences
        .where((reference) => reference.category == category)
        .toList();
  }

  Artwork? artworkById(String id) {
    for (final artwork in _artworks) {
      if (artwork.id == id) {
        return artwork;
      }
    }

    return null;
  }
}
