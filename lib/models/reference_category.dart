enum ReferenceCategory {
  portrait,
  landscape,
  architecture,
  stillLife,
  abstract,
  icon,
}

extension ReferenceCategoryExtension on ReferenceCategory {
  String get displayName {
    switch (this) {
      case ReferenceCategory.portrait:
        return 'Portraits';
      case ReferenceCategory.landscape:
        return 'Landscapes';
      case ReferenceCategory.architecture:
        return 'Architecture';
      case ReferenceCategory.stillLife:
        return 'Still Life';
      case ReferenceCategory.abstract:
        return 'Abstract';
      case ReferenceCategory.icon:
        return 'Icon';
    }
  }

  String get thumbnailAsset {
    switch (this) {
      case ReferenceCategory.portrait:
        return 'assets/category_thumbnails/portraits.jpg';

      case ReferenceCategory.landscape:
        return 'assets/category_thumbnails/landscapes.jpg';

      case ReferenceCategory.architecture:
        return 'assets/category_thumbnails/architecture.jpg';

      case ReferenceCategory.stillLife:
        return 'assets/category_thumbnails/stilllife.jpg';

      case ReferenceCategory.abstract:
        return 'assets/category_thumbnails/abstract.jpg';

      case ReferenceCategory.icon:
        return 'assets/category_thumbnails/icon.jpg';
    }
  }
}
