import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:printing/printing.dart';
import '../models/reference_category.dart';
import '../models/reference_document.dart';
import 'library_image_cache.dart';
import 'local_user_session.dart';
import 'network_availability.dart';
import 'document_file_cache.dart';

class DocumentService {
  DocumentService(this.client);
  final SupabaseClient client;
  static const bucket = 'reference-documents';
  final Map<String, Future<Uint8List?>> _thumbnails = {};
  Future<Uint8List?> thumbnail(
    ReferenceDocument doc,
  ) => _thumbnails.putIfAbsent(doc.id, () async {
    if (doc.fileType != 'pdf') return null;
    try {
      final cached = await DocumentFileCache.instance.read(
        userId,
        '${doc.id}-thumbnail',
      );
      if (cached != null) return cached;
      final original = await DocumentFileCache.instance.read(userId, doc.id);
      if (original == null) return null;
      final page = await Printing.raster(original, pages: [0], dpi: 36).first;
      final bytes = await page.toPng();
      await DocumentFileCache.instance.write(
        userId,
        '${doc.id}-thumbnail',
        bytes,
      );
      return bytes;
    } catch (_) {
      return null;
    }
  });
  String get userId =>
      client.auth.currentUser?.id ??
      LocalUserSession.effectiveUserId ??
      (throw StateError('Sign in to access documents.'));
  bool get offline =>
      LocalUserSession.isOfflineActive ||
      ConnectivityMonitor.instance.isOffline;
  Future<void> _cache(String id, Uint8List bytes) =>
      DocumentFileCache.instance.write(userId, id, bytes);

  Future<List<ReferenceDocument>> list(ReferenceCategory category) async {
    _thumbnails.clear();
    if (category.isMyArt) return [];
    final scope = 'documents:${category.id}';
    final owner = userId;
    List<dynamic>? rows;
    if (!offline) {
      try {
        rows = await client
            .from('reference_documents')
            .select()
            .eq('category_id', category.id)
            .order('date_added', ascending: false);
        await LibraryImageCache.write(owner, scope, rows);
      } catch (_) {
        rows = await LibraryImageCache.read(owner, scope);
        if (rows == null) rethrow;
      }
    } else {
      rows = await LibraryImageCache.read(owner, scope);
    }
    if (owner != userId) {
      throw StateError('The signed-in account changed. Reopen this category.');
    }
    return (rows ?? [])
        .map(
          (r) =>
              ReferenceDocument.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<void> upload(
    ReferenceCategory category,
    String filename,
    Uint8List bytes,
  ) async {
    if (offline) {
      throw StateError('Connect to the internet to upload documents.');
    }
    final type = DocumentFormat.validate(filename, bytes.length);
    final id = const Uuid().v4();
    final path = '$userId/$id.$type';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: DocumentFormat.mimeTypes[type]),
        );
    try {
      await client.from('reference_documents').insert({
        'id': id,
        'user_id': userId,
        'category_id': category.id,
        'filename': filename,
        'file_type': type,
        'storage_path': path,
        'size_bytes': bytes.length,
        'title': filename,
      });
    } catch (_) {
      await client.storage.from(bucket).remove([path]);
      rethrow;
    }
    try {
      await _cache(id, bytes);
    } catch (_) {
      /* The server copy is saved. */
    }
  }

  Future<List<ReferenceDocument>> search(
    String query, {
    bool favoritesOnly = false,
  }) async {
    final rows = await client
        .from('reference_documents')
        .select()
        .order('date_added', ascending: false);
    final words = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return rows.map(ReferenceDocument.fromJson).where((doc) {
      if (favoritesOnly && !doc.isFavorite) return false;
      final text =
          '${doc.filename} ${doc.title} ${doc.notes} ${doc.keywords.join(' ')}'
              .toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  Future<Uint8List> bytes(ReferenceDocument doc) async {
    final owner = userId;
    Uint8List? cached;
    try {
      cached = await DocumentFileCache.instance.read(owner, doc.id);
    } catch (_) {
      if (offline) rethrow;
    }
    if (owner != userId) {
      throw StateError('The signed-in account changed. Reopen this document.');
    }
    if (cached != null) return cached;
    if (offline) {
      throw StateError(
        'Open this document online once to keep a copy on this device.',
      );
    }
    final bytes = await client.storage.from(bucket).download(doc.storagePath);
    if (owner != userId) {
      throw StateError('The signed-in account changed. Reopen this document.');
    }
    try {
      await DocumentFileCache.instance.write(owner, doc.id, bytes);
    } catch (_) {
      /* Online viewing still works if the cache is full. */
    }
    _thumbnails.remove(doc.id);
    return bytes;
  }

  Future<void> update(
    ReferenceDocument doc, {
    required String title,
    required String notes,
    required List<String> keywords,
    required bool favorite,
  }) async {
    if (offline) {
      throw StateError('Connect to the internet to edit document details.');
    }
    await client
        .from('reference_documents')
        .update({
          'title': title,
          'notes': notes,
          'keywords': keywords,
          'is_favorite': favorite,
        })
        .eq('id', doc.id);
  }

  Future<void> remove(ReferenceDocument doc) async {
    if (offline) {
      throw StateError('Connect to the internet to remove documents.');
    }
    await client.storage.from(bucket).remove([doc.storagePath]);
    await client.from('reference_documents').delete().eq('id', doc.id);
    await DocumentFileCache.instance.remove(userId, doc.id);
    await DocumentFileCache.instance.remove(userId, '${doc.id}-thumbnail');
  }
}
