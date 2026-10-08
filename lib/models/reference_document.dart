class ReferenceDocument {
  const ReferenceDocument({
    required this.id,
    required this.filename,
    required this.fileType,
    required this.storagePath,
    required this.sizeBytes,
    required this.dateAdded,
    required this.title,
    this.notes = '',
    this.keywords = const [],
    this.isFavorite = false,
  });
  final String id, filename, fileType, storagePath, title, notes;
  final int sizeBytes;
  final DateTime dateAdded;
  final List<String> keywords;
  final bool isFavorite;
  factory ReferenceDocument.fromJson(Map<String, dynamic> row) =>
      ReferenceDocument(
        id: row['id'] as String,
        filename: row['filename'] as String,
        fileType: row['file_type'] as String,
        storagePath: row['storage_path'] as String,
        sizeBytes: (row['size_bytes'] as num).toInt(),
        dateAdded: DateTime.parse(row['date_added'] as String),
        title: row['title'] as String,
        notes: row['notes'] as String? ?? '',
        keywords: List<String>.from(row['keywords'] as List? ?? []),
        isFavorite: row['is_favorite'] == true,
      );
}

class DocumentFormat {
  static const mimeTypes = {
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'rtf': 'application/rtf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };
  static const maxBytes = 25 * 1024 * 1024;
  static String extension(String filename) =>
      filename.split('.').last.toLowerCase();
  static String validate(String filename, int size) {
    final type = extension(filename);
    if (!mimeTypes.containsKey(type)) {
      throw const FormatException('Choose a PDF, TXT, RTF, DOC, or DOCX file.');
    }
    if (filename.length > 255) {
      throw const FormatException('The filename is too long.');
    }
    if (size <= 0) throw const FormatException('The document is empty.');
    if (size > maxBytes) {
      throw const FormatException('Documents must be 25 MB or smaller.');
    }
    return type;
  }
}
