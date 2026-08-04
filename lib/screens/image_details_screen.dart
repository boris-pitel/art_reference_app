import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import '../services/category_service.dart';
import '../services/image_asset_service.dart';
import '../services/image_save_service.dart';
import '../services/keyword_service.dart';
import '../widgets/image_keywords_section.dart';

class _ExportImageData {
  const _ExportImageData(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
  String get extension => mimeType == 'image/png' ? 'png' : 'jpg';
}

Future<_ExportImageData> _downloadExportImage(String imageUrl) async {
  final response = await http.get(Uri.parse(imageUrl));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      'Image download failed with status ${response.statusCode}.',
    );
  }
  if (response.bodyBytes.isEmpty) {
    throw StateError('The downloaded image is empty.');
  }
  final header = response.headers['content-type']?.toLowerCase() ?? '';
  final bytes = response.bodyBytes;
  final mimeType =
      header.contains('png') ||
          (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50)
      ? 'image/png'
      : 'image/jpeg';
  return _ExportImageData(bytes, mimeType);
}

Future<void> _shareExportImage(
  BuildContext context,
  String imageUrl,
  String imageId,
) async {
  Rect? origin;
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    origin = renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
  final image = await _downloadExportImage(imageUrl);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          image.bytes,
          mimeType: image.mimeType,
          name: 'associated_image_$imageId.${image.extension}',
        ),
      ],
      subject: 'Associated Painter Reference Image',
      sharePositionOrigin: origin,
    ),
  );
}

Future<void> _saveExportImage(String imageUrl, String imageId) async {
  final image = await _downloadExportImage(imageUrl);
  await ImageSaveService.save(
    image.bytes,
    fileName: 'associated_image_$imageId.${image.extension}',
  );
}

enum _AssociatedImageAction { open, share, save, delete }

enum _ImageAction { move }

class _AiAnalysis {
  const _AiAnalysis({
    required this.title,
    required this.description,
    required this.keywords,
    required this.subjectType,
    required this.lighting,
    required this.composition,
    required this.dominantColors,
    required this.artNotes,
  });

  final String title;
  final String description;
  final List<String> keywords;
  final String subjectType;
  final String lighting;
  final String composition;
  final List<String> dominantColors;
  final String artNotes;

  factory _AiAnalysis.fromMap(Map<dynamic, dynamic> data) {
    return _AiAnalysis(
      title: _stringValue(data['title'] ?? data['ai_title']),
      description: _stringValue(data['description'] ?? data['ai_description']),
      keywords: _stringList(data['keywords'] ?? data['ai_keywords']),
      subjectType: _stringValue(
        data['subject_type'] ?? data['ai_subject_type'],
      ),
      lighting: _stringValue(data['lighting'] ?? data['ai_lighting']),
      composition: _stringValue(data['composition'] ?? data['ai_composition']),
      dominantColors: _stringList(
        data['dominant_colors'] ?? data['ai_dominant_colors'],
      ),
      artNotes: _stringValue(data['art_notes'] ?? data['ai_art_notes']),
    );
  }

  static String _stringValue(dynamic value) {
    if (value is! String) {
      return '';
    }

    return value.trim();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

typedef _MetadataDraft = ({
  String? title,
  String? notes,
  String? author,
  bool isFavorite,
});

class ImageDetailsScreen extends StatefulWidget {
  const ImageDetailsScreen({
    super.key,
    required this.imageId,
    required this.imageUrl,
  });

  final String imageId;
  final String imageUrl;

  @override
  State<ImageDetailsScreen> createState() => _ImageDetailsScreenState();
}

class _ImageDetailsScreenState extends State<ImageDetailsScreen>
    with WidgetsBindingObserver {
  final TextEditingController _titleController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _authorController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  final Set<String> _deletingAssociatedImageIds = <String>{};
  final Set<String> _sharingAssociatedImageIds = <String>{};
  final Set<String> _savingAssociatedImageIds = <String>{};
  final GlobalKey<ImageKeywordsSectionState> _keywordsSectionKey =
      GlobalKey<ImageKeywordsSectionState>();
  final Set<String> _addingAiKeywords = <String>{};
  final Set<String> _attachedKeywords = <String>{};

  bool _isLoadingMetadata = true;
  Timer? _metadataSaveDebounce;
  Future<bool>? _metadataSaveFuture;
  _MetadataDraft? _lastSavedMetadata;
  bool _hasSavedMetadataChanges = false;
  bool _isSavingMetadata = false;
  bool _isExiting = false;
  bool _allowPop = false;
  bool _isAiAnalysisExpanded = false;
  bool _isMovingImage = false;
  bool _isFavorite = false;

  bool _isAnalyzingImage = false;

  bool _isLoadingAssociatedImages = true;
  bool _isUploadingAssociatedImage = false;

  String? _metadataError;
  String? _aiAnalysisError;
  String? _associatedImagesError;

  String _aiAnalysisStatus = 'not_analyzed';

  _AiAnalysis? _aiAnalysis;

  List<ImageAssetInfo> _associatedImages = [];

  SupabaseClient get _supabase => Supabase.instance.client;

  ImageAssetService get _imageAssetService => ImageAssetService(_supabase);

  KeywordService get _keywordService => KeywordService(_supabase);

  String get _userId {
    final normalizedEmail = _supabase.auth.currentUser?.email
        ?.trim()
        .toLowerCase();

    if (normalizedEmail == null || normalizedEmail.isEmpty) {
      throw StateError('You must be signed in before accessing image details.');
    }

    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$normalizedEmail',
    );
  }

  bool get _cameraIsAvailable {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  _MetadataDraft get _currentMetadata => (
    title: _normalizedNullableText(_titleController.text),
    notes: _normalizedNullableText(_notesController.text),
    author: _normalizedNullableText(_authorController.text),
    isFavorite: _isFavorite,
  );

  bool get _hasUnsavedMetadata =>
      !_isLoadingMetadata && _lastSavedMetadata != _currentMetadata;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleController.addListener(_metadataChanged);
    _notesController.addListener(_metadataChanged);
    _authorController.addListener(_metadataChanged);

    _loadMetadata();
    _loadAssociatedImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metadataSaveDebounce?.cancel();
    _titleController.dispose();
    _notesController.dispose();
    _authorController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _metadataSaveDebounce?.cancel();
      if (_hasUnsavedMetadata) {
        unawaited(_saveMetadata(showSuccessMessage: false));
      }
    }
  }

  void _metadataChanged() {
    if (_isLoadingMetadata || _isExiting) {
      return;
    }
    _metadataSaveDebounce?.cancel();
    _metadataSaveDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _hasUnsavedMetadata) {
        unawaited(_saveMetadata(showSuccessMessage: false));
      }
    });
  }

  Future<void> _loadMetadata() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingMetadata = true;
      _metadataError = null;
      _aiAnalysisError = null;
    });

    try {
      final response = await _supabase.functions.invoke(
        'get-image-metadata',
        method: HttpMethod.get,
        headers: {'x-user-id': _userId, 'x-image-id': widget.imageId},
      );

      final data = response.data;

      if (data is! Map) {
        throw StateError(
          'get-image-metadata returned an unexpected '
          'response: $data',
        );
      }

      if (data['error'] != null) {
        throw StateError(data['error'].toString());
      }

      final loadedAnalysis = _hasAiAnalysisData(data)
          ? _AiAnalysis.fromMap(data)
          : null;

      final analysisStatus =
          data['ai_analysis_status']?.toString().trim() ?? 'not_analyzed';

      final storedAnalysisError = data['ai_analysis_error']?.toString().trim();

      if (!mounted) {
        return;
      }

      _titleController.text = data['title'] as String? ?? '';

      _notesController.text = data['notes'] as String? ?? '';

      _authorController.text = data['source_url'] as String? ?? '';

      setState(() {
        _isFavorite = data['is_favorite'] == true;
        _lastSavedMetadata = _currentMetadata;

        _aiAnalysis = loadedAnalysis;
        _aiAnalysisStatus = analysisStatus;

        if (storedAnalysisError != null && storedAnalysisError.isNotEmpty) {
          _aiAnalysisError = storedAnalysisError;
        }

        _isLoadingMetadata = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lastSavedMetadata ??= _currentMetadata;
        _isLoadingMetadata = false;
        _metadataError = 'Unable to load image details.\n$error';
      });
    }
  }

  bool _hasAiAnalysisData(Map<dynamic, dynamic> data) {
    final aiTitle = data['ai_title'];

    if (aiTitle is String && aiTitle.trim().isNotEmpty) {
      return true;
    }

    final aiDescription = data['ai_description'];

    return aiDescription is String && aiDescription.trim().isNotEmpty;
  }

  Future<bool> _saveMetadata({bool showSuccessMessage = true}) {
    final existingSave = _metadataSaveFuture;
    if (existingSave != null) {
      return existingSave;
    }
    if (!_hasUnsavedMetadata) {
      return Future<bool>.value(true);
    }

    final operation = _performMetadataSave(
      _currentMetadata,
      showSuccessMessage: showSuccessMessage,
    );
    _metadataSaveFuture = operation;
    return operation;
  }

  Future<bool> _performMetadataSave(
    _MetadataDraft draft, {
    required bool showSuccessMessage,
  }) async {
    if (mounted) {
      setState(() {
        _isSavingMetadata = true;
        _metadataError = null;
      });
    }

    try {
      final response = await _supabase.functions.invoke(
        'save-image-metadata',
        body: {
          'user_id': _userId,
          'image_id': widget.imageId,
          'title': draft.title,
          'notes': draft.notes,
          'source_url': draft.author,
          'is_favorite': draft.isFavorite,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw StateError(
          'save-image-metadata returned an unexpected response: $data',
        );
      }
      if (data['saved'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'The metadata was not saved.',
        );
      }

      _lastSavedMetadata = draft;
      _hasSavedMetadataChanges = true;
      if (mounted && showSuccessMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image details saved.')));
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _metadataError = 'Unable to save image details.\n$error';
        });
        if (_isExiting || showSuccessMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to save. Please try leaving again.'),
            ),
          );
        }
      }
      return false;
    } finally {
      _metadataSaveFuture = null;
      if (mounted) {
        setState(() {
          _isSavingMetadata = false;
        });
        if (_hasUnsavedMetadata && !_isExiting) {
          _metadataChanged();
        }
      }
    }
  }

  Future<bool> _saveAllMetadata() async {
    while (_hasUnsavedMetadata || _metadataSaveFuture != null) {
      final saved = await _saveMetadata(showSuccessMessage: false);
      if (!saved) {
        return false;
      }
    }
    return true;
  }

  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop || _isExiting) {
      return;
    }

    _metadataSaveDebounce?.cancel();
    if (_isLoadingMetadata) {
      _completePop(result);
      return;
    }

    setState(() {
      _isExiting = true;
    });

    final saved = await _saveAllMetadata();
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isExiting = false;
      });
      return;
    }

    _completePop(result);
  }

  void _completePop(Object? result) {
    setState(() {
      _allowPop = true;
    });
    final popResult = result == true || _hasSavedMetadataChanges
        ? true
        : result;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(popResult);
      }
    });
  }

  Future<void> _analyzeImage() async {
    if (_isAnalyzingImage) {
      return;
    }

    setState(() {
      _isAnalyzingImage = true;
      _aiAnalysisStatus = 'analyzing';
      _aiAnalysisError = null;
    });

    try {
      final response = await _supabase.functions.invoke(
        'analyze-image',
        body: {'imageId': widget.imageId},
      );

      final data = response.data;

      if (data is! Map) {
        throw StateError(
          'analyze-image returned an unexpected '
          'response: $data',
        );
      }

      if (data['success'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'The AI analysis was not completed.',
        );
      }

      final analysisData = data['analysis'];

      if (analysisData is! Map) {
        throw StateError('The AI response did not contain analysis data.');
      }

      final analysis = _AiAnalysis.fromMap(analysisData);

      if (!mounted) {
        return;
      }

      setState(() {
        _aiAnalysis = analysis;
        _aiAnalysisStatus = 'completed';
        _isAiAnalysisExpanded = true;
        _isAnalyzingImage = false;
        _aiAnalysisError = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI analysis completed.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzingImage = false;
        _aiAnalysisStatus = 'failed';
        _aiAnalysisError = 'Unable to analyze this image.\n$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to analyze this image.')),
      );
    }
  }

  Future<void> _loadAssociatedImages() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingAssociatedImages = true;
      _associatedImagesError = null;
    });

    try {
      final images = await _imageAssetService.listAssociatedImages(
        widget.imageId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _associatedImages = images;
        _isLoadingAssociatedImages = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingAssociatedImages = false;
        _associatedImagesError = 'Unable to load associated images.\n$error';
      });
    }
  }

  Future<void> _pickAssociatedImage(ImageSource source) async {
    if (_isUploadingAssociatedImage) {
      return;
    }

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (pickedFile == null) {
        return;
      }

      final imageBytes = await pickedFile.readAsBytes();

      await _uploadAssociatedImage(imageBytes);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _associatedImagesError = 'Unable to select the image.\n$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to select the image.')),
      );
    }
  }

  Future<void> _uploadAssociatedImage(Uint8List imageBytes) async {
    if (_isUploadingAssociatedImage) {
      return;
    }

    setState(() {
      _isUploadingAssociatedImage = true;
      _associatedImagesError = null;
    });

    try {
      await _imageAssetService.uploadAssociatedImage(
        imageBytes,
        widget.imageId,
      );

      await _loadAssociatedImages();

      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingAssociatedImage = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Associated image added.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingAssociatedImage = false;
        _associatedImagesError = 'Unable to add the associated image.\n$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to add the associated image.')),
      );
    }
  }

  Future<void> _handleAssociatedImageAction(
    _AssociatedImageAction action,
    ImageAssetInfo image,
  ) async {
    switch (action) {
      case _AssociatedImageAction.open:
        _openAssociatedImage(image);
        break;

      case _AssociatedImageAction.share:
        await _shareAssociatedImage(image);
        break;

      case _AssociatedImageAction.save:
        await _saveAssociatedImage(image);
        break;

      case _AssociatedImageAction.delete:
        await _confirmAndRemoveAssociatedImage(image);
        break;
    }
  }

  bool _isExportingAssociatedImage(String imageId) =>
      _sharingAssociatedImageIds.contains(imageId) ||
      _savingAssociatedImageIds.contains(imageId);

  Future<void> _shareAssociatedImage(ImageAssetInfo image) async {
    if (_isExportingAssociatedImage(image.id)) return;
    setState(() => _sharingAssociatedImageIds.add(image.id));
    try {
      await _shareExportImage(context, image.imageUrl, image.id);
    } catch (error) {
      if (mounted) {
        _showAssociatedMessage('Unable to share image: $error');
      }
    } finally {
      if (mounted) setState(() => _sharingAssociatedImageIds.remove(image.id));
    }
  }

  Future<void> _saveAssociatedImage(ImageAssetInfo image) async {
    if (_isExportingAssociatedImage(image.id)) return;
    setState(() => _savingAssociatedImageIds.add(image.id));
    try {
      await _saveExportImage(image.imageUrl, image.id);
      if (mounted) {
        _showAssociatedMessage(
          kIsWeb ? 'Image downloaded.' : 'Image saved to Photos.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showAssociatedMessage('Unable to save image: $error');
      }
    } finally {
      if (mounted) setState(() => _savingAssociatedImageIds.remove(image.id));
    }
  }

  void _showAssociatedMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndRemoveAssociatedImage(ImageAssetInfo image) async {
    if (_deletingAssociatedImageIds.contains(image.id)) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete associated image?'),
          content: const Text(
            'This image will be removed from this '
            'reference.\n\n'
            'If it is not connected to any other '
            'reference, its original file and '
            'thumbnail will also be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _deletingAssociatedImageIds.add(image.id);
      _associatedImagesError = null;
    });

    try {
      await _imageAssetService.removeAssociatedImage(
        parentImageId: widget.imageId,
        childImageId: image.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _associatedImages.removeWhere(
          (existingImage) => existingImage.id == image.id,
        );

        _deletingAssociatedImageIds.remove(image.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Associated image deleted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deletingAssociatedImageIds.remove(image.id);

        _associatedImagesError =
            'Unable to delete the associated image.\n'
            '$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete the associated image.')),
      );
    }
  }

  void _openAssociatedImage(ImageAssetInfo image) {
    _openZoomableImage(
      imageUrl: image.imageUrl,
      heroTag: 'associated-image-${image.id}',
      exportImageId: image.id,
    );
  }

  void _openMainImage() {
    _openZoomableImage(
      imageUrl: widget.imageUrl,
      heroTag: 'main-image-${widget.imageId}',
    );
  }

  void _openZoomableImage({
    required String imageUrl,
    required String heroTag,
    String? exportImageId,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return _ZoomableImageScreen(
            imageUrl: imageUrl,
            heroTag: heroTag,
            exportImageId: exportImageId,
          );
        },
      ),
    );
  }

  Future<void> _moveImage() async {
    if (_isMovingImage) {
      return;
    }

    setState(() {
      _isMovingImage = true;
    });

    try {
      final categoryService = CategoryService(_supabase);
      final results = await Future.wait<dynamic>([
        categoryService.listCategories(),
        _imageAssetService.listImageCategoryCodes(widget.imageId),
      ]);

      final allCategories = results[0] as List<ReferenceCategory>;
      final currentCodes = (results[1] as List<String>).toSet();
      final currentCategories = allCategories
          .where((category) => currentCodes.contains(category.databaseCode))
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      if (currentCategories.isEmpty) {
        throw StateError('This image is not assigned to any category.');
      }

      final moveSelection =
          await showDialog<({ReferenceCategory from, ReferenceCategory to})>(
            context: context,
            builder: (dialogContext) {
              ReferenceCategory fromCategory = currentCategories.first;
              ReferenceCategory? toCategory;

              return StatefulBuilder(
                builder: (context, setDialogState) {
                  final destinationCategories = allCategories
                      .where(
                        (category) =>
                            category.databaseCode != fromCategory.databaseCode,
                      )
                      .toList(growable: false);

                  if (toCategory != null &&
                      toCategory!.databaseCode == fromCategory.databaseCode) {
                    toCategory = null;
                  }

                  return AlertDialog(
                    title: const Text('Move Reference'),
                    content: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (currentCategories.length > 1) ...[
                            const Text('Move from'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<ReferenceCategory>(
                              initialValue: fromCategory,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              items: currentCategories
                                  .map(
                                    (category) => DropdownMenuItem(
                                      value: category,
                                      child: Text(category.displayName),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setDialogState(() {
                                  fromCategory = value;
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                          ] else ...[
                            Text(
                              'Current category: ${fromCategory.displayName}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 18),
                          ],
                          const Text('Move to'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<ReferenceCategory>(
                            initialValue: toCategory,
                            decoration: const InputDecoration(
                              hintText: 'Choose a destination category',
                              border: OutlineInputBorder(),
                            ),
                            items: destinationCategories
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(category.displayName),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              setDialogState(() {
                                toCategory = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: toCategory == null
                            ? null
                            : () {
                                Navigator.of(
                                  dialogContext,
                                ).pop((from: fromCategory, to: toCategory!));
                              },
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: const Text('Move'),
                      ),
                    ],
                  );
                },
              );
            },
          );

      if (moveSelection == null || !mounted) {
        return;
      }

      await _imageAssetService.moveImageToCategory(
        imageId: widget.imageId,
        fromCategory: moveSelection.from,
        toCategory: moveSelection.to,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image moved to ${moveSelection.to.displayName}.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to move image: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isMovingImage = false;
        });
      }
    }
  }

  void _handleKeywordsChanged(List<String> keywords) {
    if (!mounted) {
      return;
    }

    setState(() {
      _attachedKeywords
        ..clear()
        ..addAll(keywords.map((keyword) => keyword.trim().toLowerCase()));
    });
  }

  Future<void> _addAiKeyword(String keyword) async {
    final normalizedKeyword = keyword.trim();
    final normalizedKey = normalizedKeyword.toLowerCase();

    if (normalizedKeyword.isEmpty ||
        _addingAiKeywords.contains(normalizedKey) ||
        _attachedKeywords.contains(normalizedKey)) {
      return;
    }

    setState(() {
      _addingAiKeywords.add(normalizedKey);
    });

    try {
      await _keywordService.addKeyword(
        imageId: widget.imageId,
        keyword: normalizedKeyword,
      );

      await _keywordsSectionKey.currentState?.reloadKeywords();

      if (!mounted) {
        return;
      }

      setState(() {
        _attachedKeywords.add(normalizedKey);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keyword "$normalizedKeyword" added.')),
      );
    } on DuplicateKeywordException {
      await _keywordsSectionKey.currentState?.reloadKeywords();

      if (!mounted) {
        return;
      }

      setState(() {
        _attachedKeywords.add(normalizedKey);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add "$normalizedKeyword".\n$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingAiKeywords.remove(normalizedKey);
        });
      }
    }
  }

  String? _normalizedNullableText(String value) {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        unawaited(_handlePop(didPop, result));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Image Details'),
          actions: [
            IconButton(
              onPressed: _isLoadingMetadata || _isSavingMetadata
                  ? null
                  : () {
                      setState(() {
                        _isFavorite = !_isFavorite;
                      });
                      _metadataChanged();
                    },
              icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
              tooltip: _isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
            ),
            PopupMenuButton<_ImageAction>(
              enabled: !_isMovingImage,
              tooltip: 'Image actions',
              onSelected: (action) async {
                switch (action) {
                  case _ImageAction.move:
                    await _moveImage();
                }
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem<_ImageAction>(
                    value: _ImageAction.move,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_move_outline),
                      title: Text('Move...'),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;

            final calculatedImageHeight = availableHeight * 0.55;

            final imageHeight = math.min(
              700.0,
              math.max(320.0, calculatedImageHeight),
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildImageViewer(context, imageHeight),
                const SizedBox(height: 24),
                _buildMetadataSection(context),
                const SizedBox(height: 24),

                ImageKeywordsSection(
                  key: _keywordsSectionKey,
                  imageId: widget.imageId,
                  onKeywordsChanged: _handleKeywordsChanged,
                ),

                const SizedBox(height: 24),
                _buildAiAnalysisSection(context),
                const SizedBox(height: 24),
                _buildAssociatedImagesSection(context),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageViewer(BuildContext context, double imageHeight) {
    final heroTag = 'main-image-${widget.imageId}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openMainImage,
        child: Container(
          width: double.infinity,
          height: imageHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image.network(
                  widget.imageUrl,
                  width: double.infinity,
                  height: imageHeight,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }

                    final expectedBytes = loadingProgress.expectedTotalBytes;

                    final value = expectedBytes == null
                        ? null
                        : loadingProgress.cumulativeBytesLoaded / expectedBytes;

                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(value: value),
                          const SizedBox(height: 16),
                          const Text('Loading full image...'),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 52),
                            SizedBox(height: 12),
                            Text(
                              'Unable to load '
                              'the full image.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_full, size: 20, color: Colors.white),
                        SizedBox(width: 7),
                        Text(
                          'Open image',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reference Information',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            if (_isFavorite)
              Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingMetadata)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading image details...'),
                ],
              ),
            ),
          )
        else ...[
          if (_metadataError != null) ...[
            _buildErrorContainer(
              context,
              _metadataError!,
              actionLabel: 'Try Again',
              onAction: _loadMetadata,
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Enter a title for this reference',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText:
                  'Add composition ideas, color '
                  'notes, or painting plans',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 72),
                child: Icon(Icons.notes_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _authorController,

            decoration: const InputDecoration(
              labelText: 'Author',
              hintText: 'Artist, photographer, or creator',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Favorite'),
            subtitle: const Text(
              'Mark this image as an important '
              'reference',
            ),
            value: _isFavorite,
            onChanged: _isSavingMetadata
                ? null
                : (value) {
                    setState(() {
                      _isFavorite = value;
                    });
                    _metadataChanged();
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildAiAnalysisSection(BuildContext context) {
    final analysis = _aiAnalysis;
    final buttonLabel = _isAnalyzingImage
        ? 'Analyzing...'
        : analysis == null
        ? _aiAnalysisStatus == 'failed'
              ? 'Retry AI Analysis'
              : 'Analyze with AI'
        : _isAiAnalysisExpanded
        ? 'Hide AI Analysis'
        : 'Show AI Analysis';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoadingMetadata || _isAnalyzingImage
                ? null
                : analysis == null
                ? _analyzeImage
                : () {
                    setState(() {
                      _isAiAnalysisExpanded = !_isAiAnalysisExpanded;
                    });
                  },
            icon: _isAnalyzingImage
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    analysis == null
                        ? Icons.auto_awesome
                        : _isAiAnalysisExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
            label: Text(buttonLabel),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'AI analysis is optional. The image is sent '
          'for analysis only when you press the button.',
        ),
        const SizedBox(height: 16),
        if (_isLoadingMetadata)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_aiAnalysisError != null) ...[
            _buildErrorContainer(context, _aiAnalysisError!),
            const SizedBox(height: 16),
          ],
          if (_isAnalyzingImage) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text(
              'Analyzing subject, lighting, '
              'composition, colors, and painting '
              'notes...',
            ),
            const SizedBox(height: 16),
          ],
          if (analysis != null && _isAiAnalysisExpanded) ...[
            _buildAiAnalysisCard(context, analysis),
            const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }

  Widget _buildAiAnalysisCard(BuildContext context, _AiAnalysis analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis.title.isNotEmpty) ...[
            Text(
              analysis.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
          ],
          _buildAiTextSection(
            context,
            title: 'Description',
            value: analysis.description,
            icon: Icons.description_outlined,
          ),
          _buildAiTextSection(
            context,
            title: 'Subject Type',
            value: analysis.subjectType,
            icon: Icons.category_outlined,
          ),
          _buildAiTextSection(
            context,
            title: 'Lighting',
            value: analysis.lighting,
            icon: Icons.light_mode_outlined,
          ),
          _buildAiTextSection(
            context,
            title: 'Composition',
            value: analysis.composition,
            icon: Icons.crop_outlined,
          ),
          if (analysis.keywords.isNotEmpty)
            _buildAiChipSection(
              context,
              title: 'Keywords',
              values: analysis.keywords,
              icon: Icons.sell_outlined,
              allowAddingAsKeyword: true,
            ),
          if (analysis.dominantColors.isNotEmpty)
            _buildAiChipSection(
              context,
              title: 'Dominant Colors',
              values: analysis.dominantColors,
              icon: Icons.palette_outlined,
            ),
          _buildAiTextSection(
            context,
            title: 'Notes for the Artist',
            value: analysis.artNotes,
            icon: Icons.brush_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildAiTextSection(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    bool isLast = false,
  }) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _buildAiChipSection(
    BuildContext context, {
    required String title,
    required List<String> values,
    required IconData icon,
    bool allowAddingAsKeyword = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (allowAddingAsKeyword) ...[
            const SizedBox(height: 5),
            const Text('Tap a tag to add it to your keywords.'),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map((value) {
                  if (!allowAddingAsKeyword) {
                    return Chip(
                      label: Text(value),
                      visualDensity: VisualDensity.compact,
                    );
                  }

                  final normalizedKey = value.trim().toLowerCase();
                  final isAdded = _attachedKeywords.contains(normalizedKey);
                  final isAdding = _addingAiKeywords.contains(normalizedKey);

                  return SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: isAdded || isAdding
                          ? null
                          : () async {
                              await _addAiKeyword(value);
                            },
                      icon: isAdding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : Icon(isAdded ? Icons.check : Icons.add, size: 22),
                      label: Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(110, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorContainer(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssociatedImagesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Associated Images',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            if (_associatedImages.isNotEmpty)
              Text(
                '${_associatedImages.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Add paintings, work-in-progress photos, '
          'crops, or edited versions linked to this '
          'reference.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _isUploadingAssociatedImage
                  ? null
                  : () {
                      _pickAssociatedImage(ImageSource.gallery);
                    },
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Attach Image'),
            ),
            if (_cameraIsAvailable)
              OutlinedButton.icon(
                onPressed: _isUploadingAssociatedImage
                    ? null
                    : () {
                        _pickAssociatedImage(ImageSource.camera);
                      },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            IconButton.outlined(
              onPressed:
                  _isLoadingAssociatedImages || _isUploadingAssociatedImage
                  ? null
                  : _loadAssociatedImages,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh associated images',
            ),
          ],
        ),
        if (_isUploadingAssociatedImage) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Adding associated image...'),
        ],
        if (_associatedImagesError != null) ...[
          const SizedBox(height: 16),
          _buildErrorContainer(
            context,
            _associatedImagesError!,
            actionLabel: 'Try Again',
            onAction: _isLoadingAssociatedImages ? null : _loadAssociatedImages,
          ),
        ],
        const SizedBox(height: 16),
        if (_isLoadingAssociatedImages)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading associated images...'),
                ],
              ),
            ),
          )
        else if (_associatedImages.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.collections_outlined, size: 44),
                SizedBox(height: 12),
                Text(
                  'No associated images yet.',
                  style: TextStyle(fontSize: 17),
                ),
                SizedBox(height: 6),
                Text(
                  'Use Attach Image or Camera to add '
                  'the first one.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              final columnCount = width >= 1000
                  ? 5
                  : width >= 700
                  ? 4
                  : width >= 450
                  ? 3
                  : 2;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _associatedImages.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final image = _associatedImages[index];

                  return _buildAssociatedImageTile(context, image);
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildAssociatedImageTile(BuildContext context, ImageAssetInfo image) {
    final displayUrl = image.thumbnailUrl ?? image.imageUrl;

    final isDeleting = _deletingAssociatedImageIds.contains(image.id);
    final isExporting = _isExportingAssociatedImage(image.id);
    final isBusy = isDeleting || isExporting;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isBusy
            ? null
            : () {
                _openAssociatedImage(image);
              },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              displayUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40),
                );
              },
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: PopupMenuButton<_AssociatedImageAction>(
                  enabled: !isBusy,
                  tooltip: 'Image actions',
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 22,
                  ),
                  onSelected: (action) {
                    _handleAssociatedImageAction(action, image);
                  },
                  itemBuilder: (context) {
                    return const [
                      PopupMenuItem<_AssociatedImageAction>(
                        value: _AssociatedImageAction.open,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.open_in_full_outlined),
                          title: Text('Open'),
                        ),
                      ),
                      PopupMenuItem<_AssociatedImageAction>(
                        value: _AssociatedImageAction.share,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.share_outlined),
                          title: Text('Share'),
                        ),
                      ),
                      PopupMenuItem<_AssociatedImageAction>(
                        value: _AssociatedImageAction.save,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.download_outlined),
                          title: Text('Save to Photos'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem<_AssociatedImageAction>(
                        value: _AssociatedImageAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ];
                  },
                ),
              ),
            ),
            if (!isBusy)
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.zoom_in, size: 20, color: Colors.white),
                  ),
                ),
              ),
            if (isBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImageScreen extends StatefulWidget {
  const _ZoomableImageScreen({
    required this.imageUrl,
    required this.heroTag,
    this.exportImageId,
  });

  final String imageUrl;
  final String heroTag;
  final String? exportImageId;

  @override
  State<_ZoomableImageScreen> createState() => _ZoomableImageScreenState();
}

class _ZoomableImageScreenState extends State<_ZoomableImageScreen> {
  static const double _minimumScale = 1;
  static const double _maximumScale = 8;
  static const double _doubleTapScale = 3;

  final TransformationController _transformationController =
      TransformationController();

  TapDownDetails? _doubleTapDetails;
  bool _isSharing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    if (currentScale > _minimumScale) {
      _transformationController.value = Matrix4.identity();

      return;
    }

    final tapPosition = _doubleTapDetails?.localPosition;

    if (tapPosition == null) {
      return;
    }

    final x = -tapPosition.dx * (_doubleTapScale - 1);

    final y = -tapPosition.dy * (_doubleTapScale - 1);

    _transformationController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(_doubleTapScale);
  }

  Future<void> _shareImage() async {
    final imageId = widget.exportImageId;
    if (imageId == null || _isSharing || _isSaving) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      await _shareExportImage(context, widget.imageUrl, imageId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to share image: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _saveImage() async {
    final imageId = widget.exportImageId;
    if (imageId == null || _isSharing || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _saveExportImage(widget.imageUrl, imageId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb ? 'Image downloaded.' : 'Image saved to Photos.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save image: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Image'),
        actions: [
          if (widget.exportImageId != null) ...[
            IconButton(
              onPressed: _isSharing || _isSaving ? null : _saveImage,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
              tooltip: kIsWeb ? 'Download image' : 'Save to Photos',
            ),
            IconButton(
              onPressed: _isSharing || _isSaving ? null : _shareImage,
              icon: _isSharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share_outlined),
              tooltip: 'Share image',
            ),
          ],
          IconButton(
            onPressed: _resetZoom,
            icon: const Icon(Icons.fit_screen_outlined),
            tooltip: 'Reset zoom',
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: _minimumScale,
            maxScale: _maximumScale,
            boundaryMargin: const EdgeInsets.all(120),
            clipBehavior: Clip.none,
            child: SizedBox.expand(
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: Image.network(
                    widget.imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      final expectedBytes = loadingProgress.expectedTotalBytes;

                      final value = expectedBytes == null
                          ? null
                          : loadingProgress.cumulativeBytesLoaded /
                                expectedBytes;

                      return Center(
                        child: CircularProgressIndicator(
                          value: value,
                          color: Colors.white,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 64,
                              color: Colors.white,
                            ),
                            SizedBox(height: 14),
                            Text(
                              'Unable to load image.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
