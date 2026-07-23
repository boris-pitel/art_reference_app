enum ReferenceCategory {
  portrait(
    databaseCode: 'portrait',
    displayName: 'Portraits',
    thumbnailAsset: 'assets/category_thumbnails/portraits.jpg',
  ),

  landscape(
    databaseCode: 'landscape',
    displayName: 'Landscapes',
    thumbnailAsset: 'assets/category_thumbnails/landscapes.jpg',
  ),

  architecture(
    databaseCode: 'architecture',
    displayName: 'Architecture',
    thumbnailAsset: 'assets/category_thumbnails/architecture.jpg',
  ),

  stillLife(
    databaseCode: 'still_life',
    displayName: 'Still Life',
    thumbnailAsset: 'assets/category_thumbnails/stilllife.jpg',
  ),

  abstract(
    databaseCode: 'abstract',
    displayName: 'Abstract',
    thumbnailAsset: 'assets/category_thumbnails/abstract.jpg',
  ),

  icon(
    databaseCode: 'icon',
    displayName: 'Icon',
    thumbnailAsset: 'assets/category_thumbnails/icon.jpg',
  );

  const ReferenceCategory({
    required this.databaseCode,
    required this.displayName,
    required this.thumbnailAsset,
  });

  final String databaseCode;
  final String displayName;
  final String thumbnailAsset;
}
