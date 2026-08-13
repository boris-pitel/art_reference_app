import 'dart:async';
import 'dart:math' as math;

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
import '../services/image_adjustment_service.dart';
import '../services/image_print_service.dart';
import '../services/image_save_service.dart';
import '../services/keyword_service.dart';
import '../services/user_activity_logger.dart';
import '../widgets/image_keywords_section.dart';
import '../widgets/home_button.dart';
import 'ai_image_edit_screen.dart';
import 'image_adjustment_screen.dart';
import 'recipient_picker_screen.dart';

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

enum _AssociatedImageAction { open, editImage, share, save, print, delete }

enum _ImageAction { print, move, sendToFriend }

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
  bool isFinishedArtwork,
});

class ImageDetailsNavigationItem {
  const ImageDetailsNavigationItem({
    required this.imageId,
    required this.imageUrl,
    this.dateAdded,
    this.parentImageId,
  });

  final String imageId;
  final String imageUrl;
  final DateTime? dateAdded;
  final String? parentImageId;
}

class ImageDetailsScreen extends StatefulWidget {
  const ImageDetailsScreen({
    super.key,
    required this.imageId,
    required this.imageUrl,
    this.isAssociatedImage = false,
    this.parentImageId,
    this.dateAdded,
    this.navigationItems = const <ImageDetailsNavigationItem>[],
    this.navigationIndex = 0,
    this.startImageEditing = false,
    this.hasPriorChanges = false,
  });

  final String imageId;
  final String imageUrl;
  final bool isAssociatedImage;
  final String? parentImageId;
  final DateTime? dateAdded;
  final List<ImageDetailsNavigationItem> navigationItems;
  final int navigationIndex;
  final bool startImageEditing;
  final bool hasPriorChanges;

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
  final Set<String> _printingAssociatedImageIds = <String>{};
  GlobalKey<ImageKeywordsSectionState> _keywordsSectionKey =
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
  bool _isPrintingImage = false;
  bool _isSendingToFriend = false;
  bool _isFavorite = false;
  bool _isFinishedArtwork = false;
  bool _isNavigatingHorizontally = false;

  late String _currentImageId;
  late String _currentImageUrl;
  late DateTime? _currentDateAdded;
  late String? _currentParentImageId;
  late int _currentNavigationIndex;
  late List<ImageDetailsNavigationItem> _navigationItems;

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
    isFinishedArtwork: _isFinishedArtwork,
  );

  bool get _hasUnsavedMetadata =>
      !_isLoadingMetadata && _lastSavedMetadata != _currentMetadata;

  @override
  void initState() {
    super.initState();
    _currentImageId = widget.imageId;
    _currentImageUrl = widget.imageUrl;
    _currentDateAdded = widget.dateAdded;
    _currentParentImageId = widget.parentImageId;
    _currentNavigationIndex = widget.navigationIndex;
    _navigationItems = List<ImageDetailsNavigationItem>.of(
      widget.navigationItems,
    );
    WidgetsBinding.instance.addObserver(this);
    _titleController.addListener(_metadataChanged);
    _notesController.addListener(_metadataChanged);
    _authorController.addListener(_metadataChanged);

    _loadMetadata();
    if (!widget.isAssociatedImage) {
      _loadAssociatedImages();
    } else {
      _isLoadingAssociatedImages = false;
    }
    if (widget.startImageEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openMainImage(startEditing: true));
      });
    }
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
        headers: {'x-user-id': _userId, 'x-image-id': _currentImageId},
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
        _isFinishedArtwork = data['is_finished_artwork'] == true;
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
    final stopwatch = Stopwatch()..start();
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
          'image_id': _currentImageId,
          'title': draft.title,
          'notes': draft.notes,
          'source_url': draft.author,
          'is_favorite': draft.isFavorite,
          'is_finished_artwork': draft.isFinishedArtwork,
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
      UserActivityLogger.instance.record(
        operation: 'metadata_save',
        status: 'succeeded',
        targetType: widget.isAssociatedImage ? 'sketch' : 'image',
        targetId: _currentImageId,
        parentImageId: _currentParentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: const {
          'changed_fields': [
            'title',
            'notes',
            'author',
            'favorite',
            'finished_artwork',
          ],
        },
      );
      if (mounted && showSuccessMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image details saved.')));
      }
      return true;
    } catch (error) {
      final errorMessage = error is FunctionException
          ? switch (error.details) {
              final Map details =>
                details['error']?.toString() ??
                    error.reasonPhrase ??
                    'Unable to save image details.',
              final Object details => details.toString(),
              null => error.reasonPhrase ?? 'Unable to save image details.',
            }
          : error.toString();
      UserActivityLogger.instance.record(
        operation: 'metadata_save',
        status: 'failed',
        targetType: widget.isAssociatedImage ? 'sketch' : 'image',
        targetId: _currentImageId,
        parentImageId: _currentParentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        error: error,
      );
      if (mounted) {
        setState(() {
          _metadataError = 'Unable to save image details.\n$errorMessage';
        });
        if (_isExiting || showSuccessMessage) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage)));
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

  Future<void> _goHome() async {
    _metadataSaveDebounce?.cancel();
    if (!await _saveAllMetadata() || !mounted) return;
    goToCategoriesHome(context);
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
    final popResult =
        result == true || _hasSavedMetadataChanges || widget.hasPriorChanges
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
        body: {'imageId': _currentImageId},
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
        _currentImageId,
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
        _currentImageId,
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
        await _openAssociatedImage(image);
        break;

      case _AssociatedImageAction.editImage:
        await _openAssociatedImageForEditing(image);
        break;

      case _AssociatedImageAction.share:
        await _shareAssociatedImage(image);
        break;

      case _AssociatedImageAction.save:
        await _saveAssociatedImage(image);
        break;

      case _AssociatedImageAction.print:
        await _printAssociatedImage(image);
        break;

      case _AssociatedImageAction.delete:
        await _confirmAndRemoveAssociatedImage(image);
        break;
    }
  }

  Future<void> _openAssociatedImageForEditing(ImageAssetInfo image) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ImageDetailsScreen(
          imageId: image.id,
          imageUrl: image.imageUrl,
          isAssociatedImage: true,
          parentImageId: _currentImageId,
          dateAdded: image.dateAdded,
          startImageEditing: true,
        ),
      ),
    );
    if (mounted) await _loadAssociatedImages();
  }

  bool _isExportingAssociatedImage(String imageId) =>
      _sharingAssociatedImageIds.contains(imageId) ||
      _savingAssociatedImageIds.contains(imageId) ||
      _printingAssociatedImageIds.contains(imageId);

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
        parentImageId: _currentImageId,
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

  Future<void> _openAssociatedImage(ImageAssetInfo image) async {
    final stopwatch = Stopwatch()..start();
    UserActivityLogger.instance.record(
      operation: 'sketch_open',
      status: 'started',
      targetType: 'sketch',
      targetId: image.id,
      parentImageId: _currentImageId,
    );
    final navigationItems = _associatedImages
        .map(
          (item) => ImageDetailsNavigationItem(
            imageId: item.id,
            imageUrl: item.imageUrl,
            dateAdded: item.dateAdded,
          ),
        )
        .toList(growable: false);
    final navigationIndex = _associatedImages.indexWhere(
      (item) => item.id == image.id,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (context) => ImageDetailsScreen(
          imageId: image.id,
          imageUrl: image.imageUrl,
          isAssociatedImage: true,
          parentImageId: _currentImageId,
          dateAdded: image.dateAdded,
          navigationItems: navigationItems,
          navigationIndex: navigationIndex,
        ),
      ),
    );
    if (mounted) {
      await _loadAssociatedImages();
      UserActivityLogger.instance.record(
        operation: 'attached_images_refresh',
        status: 'succeeded',
        targetType: 'image',
        targetId: _currentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: const {'reason': 'returned_from_sketch'},
      );
    }
  }

  Future<void> _navigateHorizontally(int delta) async {
    if (_isNavigatingHorizontally || _navigationItems.length < 2) {
      return;
    }

    final targetIndex = _currentNavigationIndex + delta;
    if (targetIndex < 0 || targetIndex >= _navigationItems.length) {
      return;
    }

    setState(() => _isNavigatingHorizontally = true);
    _metadataSaveDebounce?.cancel();
    final saved = await _saveAllMetadata();
    if (!mounted) return;
    if (!saved) {
      setState(() => _isNavigatingHorizontally = false);
      return;
    }

    final target = _navigationItems[targetIndex];
    setState(() {
      _currentImageId = target.imageId;
      _currentImageUrl = target.imageUrl;
      _currentDateAdded = target.dateAdded;
      _currentParentImageId = target.parentImageId ?? widget.parentImageId;
      _currentNavigationIndex = targetIndex;
      _isLoadingMetadata = true;
      _lastSavedMetadata = null;
      _metadataError = null;
      _aiAnalysisError = null;
      _aiAnalysis = null;
      _aiAnalysisStatus = 'not_analyzed';
      _isAiAnalysisExpanded = false;
      _associatedImages = [];
      _associatedImagesError = null;
      _isLoadingAssociatedImages = !widget.isAssociatedImage;
      _attachedKeywords.clear();
      _addingAiKeywords.clear();
      _keywordsSectionKey = GlobalKey<ImageKeywordsSectionState>();
      _titleController.clear();
      _notesController.clear();
      _authorController.clear();
      _isFavorite = false;
      _isFinishedArtwork = false;
      _isNavigatingHorizontally = false;
    });
    await _loadMetadata();
    if (!widget.isAssociatedImage) {
      await _loadAssociatedImages();
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    // A leftward swipe advances; a rightward swipe goes back.
    unawaited(_navigateHorizontally(velocity < 0 ? 1 : -1));
  }

  Future<void> _openMainImage({bool startEditing = false}) async {
    _metadataSaveDebounce?.cancel();
    if (!await _saveAllMetadata() || !mounted) return;
    final metadataBeforeEdit = _currentMetadata;
    final result = await _openZoomableImage(
      imageUrl: _currentImageUrl,
      heroTag: 'main-image-$_currentImageId',
      exportImageId: widget.isAssociatedImage ? _currentImageId : null,
      editableParentImageId: widget.isAssociatedImage
          ? _currentParentImageId
          : null,
      createSketchParentImageId: widget.isAssociatedImage
          ? null
          : _currentImageId,
      startEditing: startEditing,
    );
    if (result != null && mounted) {
      if (!result.replacesCurrentImage) {
        await _loadAssociatedImages();
        return;
      }
      final replacementIndex = _currentNavigationIndex;
      setState(() {
        _currentImageId = result.imageId;
        _currentImageUrl = result.imageUrl;
        _metadataError = null;
        _lastSavedMetadata = null;
        _isLoadingMetadata = true;
        if (replacementIndex >= 0 &&
            replacementIndex < _navigationItems.length) {
          _navigationItems[replacementIndex] = ImageDetailsNavigationItem(
            imageId: result.imageId,
            imageUrl: result.imageUrl,
            dateAdded: _currentDateAdded,
            parentImageId: _currentParentImageId,
          );
        }
      });
      await _loadMetadata();
      if (!mounted) return;
      _titleController.text = metadataBeforeEdit.title ?? '';
      _notesController.text = metadataBeforeEdit.notes ?? '';
      _authorController.text = metadataBeforeEdit.author ?? '';
      setState(() {
        _isFavorite = metadataBeforeEdit.isFavorite;
        _isFinishedArtwork = metadataBeforeEdit.isFinishedArtwork;
      });
      await _saveMetadata(showSuccessMessage: false);
    }
  }

  Future<_EditedSketch?> _openZoomableImage({
    required String imageUrl,
    required String heroTag,
    String? exportImageId,
    String? editableParentImageId,
    String? createSketchParentImageId,
    bool startEditing = false,
  }) {
    return Navigator.of(context).push<_EditedSketch>(
      MaterialPageRoute<_EditedSketch>(
        builder: (context) {
          return _ZoomableImageScreen(
            imageUrl: imageUrl,
            heroTag: heroTag,
            exportImageId: exportImageId,
            editableParentImageId: editableParentImageId,
            createSketchParentImageId: createSketchParentImageId,
            startEditing: startEditing,
          );
        },
      ),
    );
  }

  Future<void> _printCurrentImage() async {
    if (_isMovingImage || _isPrintingImage) return;

    setState(() => _isPrintingImage = true);
    try {
      final image = await _downloadExportImage(_currentImageUrl);
      await ImagePrintService.printImage(
        imageBytes: image.bytes,
        documentName: 'Painter Reference $_currentImageId',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to print the reference: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrintingImage = false);
    }
  }

  Future<void> _sendCurrentImageToFriend() async {
    if (_isMovingImage || _isPrintingImage || _isSendingToFriend) return;

    setState(() => _isSendingToFriend = true);
    try {
      final image = await _downloadExportImage(_currentImageUrl);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RecipientPickerScreen(
            imageBytes: image.bytes,
            imageLabel: widget.isAssociatedImage ? 'sketch' : 'reference',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to prepare the image to send: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingToFriend = false);
    }
  }

  Future<void> _printAssociatedImage(ImageAssetInfo image) async {
    if (_isExportingAssociatedImage(image.id)) return;
    setState(() => _printingAssociatedImageIds.add(image.id));
    try {
      final downloadedImage = await _downloadExportImage(image.imageUrl);
      await ImagePrintService.printImage(
        imageBytes: downloadedImage.bytes,
        documentName: 'Painter Reference Sketch ${image.id}',
      );
    } catch (error) {
      if (mounted) {
        _showAssociatedMessage('Unable to print sketch: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _printingAssociatedImageIds.remove(image.id));
      }
    }
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
        _imageAssetService.listImageCategoryCodes(_currentImageId),
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
        imageId: _currentImageId,
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
        imageId: _currentImageId,
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
          title: Text(
            widget.isAssociatedImage
                ? 'Associated Image Details'
                : 'Image Details',
          ),
          actions: [
            HomeButton(
              enabled: !_isLoadingMetadata && !_isSavingMetadata,
              onPressed: _goHome,
            ),
            if (widget.isAssociatedImage)
              TextButton.icon(
                onPressed: _isLoadingMetadata || _isSavingMetadata
                    ? null
                    : _openMainImage,
                icon: const Icon(Icons.crop_rotate),
                label: const Text('Edit'),
              ),
            if (!widget.isAssociatedImage)
              IconButton(
                onPressed: _isLoadingMetadata || _isSavingMetadata
                    ? null
                    : () {
                        setState(() {
                          _isFavorite = !_isFavorite;
                        });
                        _metadataChanged();
                      },
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                ),
                tooltip: _isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
              ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          child: LayoutBuilder(
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

                  if (!widget.isAssociatedImage) ...[
                    ImageKeywordsSection(
                      key: _keywordsSectionKey,
                      imageId: _currentImageId,
                      onKeywordsChanged: _handleKeywordsChanged,
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildAiAnalysisSection(context),
                  if (!widget.isAssociatedImage) ...[
                    const SizedBox(height: 24),
                    _buildAssociatedImagesSection(context),
                  ],
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImageViewer(BuildContext context, double imageHeight) {
    final heroTag = 'main-image-$_currentImageId';

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
                  _currentImageUrl,
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
                top: 12,
                right: 12,
                child: _buildImageActionsMenu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageActionsMenu(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      child: PopupMenuButton<_ImageAction>(
        enabled: !_isMovingImage && !_isPrintingImage && !_isSendingToFriend,
        tooltip: 'Image actions',
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (action) async {
          switch (action) {
            case _ImageAction.print:
              await _printCurrentImage();
            case _ImageAction.move:
              await _moveImage();
            case _ImageAction.sendToFriend:
              await _sendCurrentImageToFriend();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem<_ImageAction>(
            value: _ImageAction.print,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.print_outlined),
              title: Text('Print'),
            ),
          ),
          const PopupMenuItem<_ImageAction>(
            value: _ImageAction.sendToFriend,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_add_alt_outlined),
              title: Text('Send to friend'),
            ),
          ),
          // A sketch isn't filed in a category, so moving it doesn't apply.
          if (!widget.isAssociatedImage) ...[
            const PopupMenuDivider(),
            const PopupMenuItem<_ImageAction>(
              value: _ImageAction.move,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.drive_file_move_outline),
                title: Text('Move...'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context) {
    final dateAdded = _currentDateAdded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.isAssociatedImage
                    ? 'Associated Image Information'
                    : 'Reference Information',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!widget.isAssociatedImage && _isFavorite)
              Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.isAssociatedImage && dateAdded != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Date added'),
            subtitle: Text(
              MaterialLocalizations.of(
                context,
              ).formatFullDate(dateAdded.toLocal()),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
          if (!widget.isAssociatedImage) ...[
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
          ],
          TextField(
            controller: _notesController,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Notes',
              hintText: widget.isAssociatedImage
                  ? 'Add progress notes, changes, materials, or painting plans'
                  : 'Add composition ideas, color notes, or painting plans',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 72),
                child: Icon(Icons.notes_outlined),
              ),
            ),
          ),
          if (widget.isAssociatedImage) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Finished painting'),
              subtitle: const Text('Show this artwork in My Art'),
              value: _isFinishedArtwork,
              onChanged: _isSavingMetadata
                  ? null
                  : (value) async {
                      final previous = _isFinishedArtwork;
                      setState(() => _isFinishedArtwork = value);
                      final saved = await _saveMetadata();
                      if (!saved && mounted) {
                        setState(() => _isFinishedArtwork = previous);
                      }
                    },
            ),
          ],
          if (!widget.isAssociatedImage) ...[
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
              subtitle: const Text('Mark this image as an important reference'),
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
              : widget.isAssociatedImage
              ? 'Do AI Analysis'
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
      key: ValueKey('associated-image-${image.id}'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isBusy
            ? null
            : () {
                unawaited(_openAssociatedImage(image));
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
                        value: _AssociatedImageAction.editImage,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit image'),
                          subtitle: Text('Crop, rotate, or straighten'),
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
                      PopupMenuItem<_AssociatedImageAction>(
                        value: _AssociatedImageAction.print,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.print_outlined),
                          title: Text('Print'),
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

class _EditedSketch {
  const _EditedSketch({
    required this.imageId,
    required this.imageUrl,
    required this.replacesCurrentImage,
  });
  final String imageId;
  final String imageUrl;
  final bool replacesCurrentImage;
}

class _ZoomableImageScreen extends StatefulWidget {
  const _ZoomableImageScreen({
    required this.imageUrl,
    required this.heroTag,
    this.exportImageId,
    this.editableParentImageId,
    this.createSketchParentImageId,
    this.startEditing = false,
  });

  final String imageUrl;
  final String heroTag;
  final String? exportImageId;
  final String? editableParentImageId;
  final String? createSketchParentImageId;
  final bool startEditing;

  @override
  State<_ZoomableImageScreen> createState() => _ZoomableImageScreenState();
}

class _ZoomableImageScreenState extends State<_ZoomableImageScreen> {
  static const double _minimumScale = 1;
  static const double _maximumScale = 8;
  static const double _doubleTapScale = 3;

  final TransformationController _transformationController =
      TransformationController();
  final ImageAdjustmentController _imageAdjustmentController =
      ImageAdjustmentController();

  TapDownDetails? _doubleTapDetails;
  bool _isSharing = false;
  bool _isSaving = false;
  bool _isLoadingEditor = false;
  bool _isApplyingEdit = false;
  bool _isEditorProcessing = false;
  String _saveProgressLabel = 'Processing image…';
  bool _hasEdited = false;
  bool _hasSavedSketchForThisWindow = false;
  bool _allowPop = false;
  Uint8List? _editingBytes;
  late String _imageUrl;
  late String? _imageId;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.imageUrl;
    _imageId = widget.exportImageId;
    if (widget.startEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startEditing();
      });
    }
  }

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
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
  }

  Future<void> _shareImage() async {
    final imageId = _imageId;
    if (imageId == null || _isSharing || _isSaving) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      await _shareExportImage(context, _imageUrl, imageId);
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
    final imageId = _imageId;
    if (imageId == null || _isSharing || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _saveExportImage(_imageUrl, imageId);
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save image: $error')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _startEditing() async {
    if (_isLoadingEditor || _isApplyingEdit) return;
    setState(() => _isLoadingEditor = true);
    try {
      final image = await _downloadExportImage(_imageUrl);
      if (mounted) {
        _resetZoom();
        setState(() => _editingBytes = image.bytes);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open the image editor: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingEditor = false);
    }
  }

  Future<void> _saveUnchangedSketch() async {
    if (_isLoadingEditor || _isApplyingEdit) return;
    setState(() {
      _isLoadingEditor = true;
      _saveProgressLabel = 'Preparing sketch…';
    });
    try {
      final stopwatch = Stopwatch()..start();
      final image = await _downloadExportImage(_imageUrl);
      UserActivityLogger.instance.record(
        operation: 'sketch_create_timing',
        status: 'started',
        targetType: 'sketch',
        parentImageId: widget.createSketchParentImageId,
        details: {'download_ms': stopwatch.elapsedMilliseconds},
      );
      final output = await ImageAdjustmentService.apply(
        bytes: image.bytes,
        angle: 0,
        crop: const Rect.fromLTWH(0, 0, 1, 1),
      );
      UserActivityLogger.instance.record(
        operation: 'sketch_create_timing',
        status: 'started',
        targetType: 'sketch',
        parentImageId: widget.createSketchParentImageId,
        details: {
          'download_ms': stopwatch.elapsedMilliseconds,
          'processing_ms': stopwatch.elapsedMilliseconds,
          'output_bytes': output.lengthInBytes,
        },
      );
      if (mounted) {
        await _applyEditedSketch(output);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create the sketch: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingEditor = false);
    }
  }

  Future<void> _openAiEditor() async {
    final sourceImageId = _imageId ?? widget.createSketchParentImageId;
    final parentImageId =
        widget.createSketchParentImageId ?? widget.editableParentImageId;
    if (sourceImageId == null || parentImageId == null || _isApplyingEdit) {
      return;
    }
    final newImageId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AiImageEditScreen(
          sourceImageId: sourceImageId,
          sourceImageUrl: _imageUrl,
          parentImageId: parentImageId,
        ),
      ),
    );
    if (newImageId == null || !mounted) return;
    try {
      final associated = await ImageAssetService(
        Supabase.instance.client,
      ).listAssociatedImages(parentImageId);
      final saved = associated
          .where((item) => item.id == newImageId)
          .firstOrNull;
      if (saved == null) {
        throw StateError('The accepted AI image could not be reloaded.');
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        _EditedSketch(
          imageId: saved.id,
          imageUrl: saved.imageUrl,
          replacesCurrentImage: false,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI image was saved, but refresh failed: $error'),
          ),
        );
      }
    }
  }

  bool _isAlreadyAttachedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('already associated') ||
        message.contains('already stored as an associated image') ||
        message.contains('duplicate key') ||
        message.contains('unique constraint');
  }

  Future<void> _applyEditedSketch(Uint8List bytes) async {
    final isCreating = widget.createSketchParentImageId != null;
    final parentId =
        widget.createSketchParentImageId ?? widget.editableParentImageId;
    final oldImageId = _imageId;
    if (parentId == null ||
        _isApplyingEdit ||
        (isCreating && _hasSavedSketchForThisWindow)) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    UserActivityLogger.instance.record(
      operation: isCreating ? 'sketch_create' : 'sketch_edit',
      status: 'started',
      targetType: 'sketch',
      targetId: oldImageId,
      parentImageId: parentId,
      details: {'output_bytes': bytes.lengthInBytes},
    );
    setState(() {
      _isApplyingEdit = true;
      if (isCreating) _hasSavedSketchForThisWindow = true;
      _saveProgressLabel = 'Uploading edited sketch…';
    });
    try {
      final service = ImageAssetService(Supabase.instance.client);
      final newImageId = await service
          .uploadAssociatedImage(bytes, parentId)
          .timeout(const Duration(seconds: 60));
      if (newImageId == parentId) {
        throw StateError('Make an adjustment before creating a sketch.');
      }
      if (!isCreating && oldImageId != null && newImageId != oldImageId) {
        if (mounted) {
          setState(() => _saveProgressLabel = 'Replacing old sketch…');
        }
        await service
            .removeAssociatedImage(
              parentImageId: parentId,
              childImageId: oldImageId,
            )
            .timeout(const Duration(seconds: 30));
      }
      if (isCreating && mounted) {
        setState(() {
          _imageId = newImageId;
          _editingBytes = null;
          _hasEdited = true;
        });
        _finishImageWindow();
        return;
      }
      if (mounted) {
        setState(() => _saveProgressLabel = 'Refreshing thumbnail…');
      }
      final images = await service
          .listAssociatedImages(parentId)
          .timeout(const Duration(seconds: 30));
      final updated = images
          .where((image) => image.id == newImageId)
          .firstOrNull;
      if (updated == null) {
        throw StateError('The edited sketch could not be reloaded.');
      }
      if (!mounted) return;
      setState(() {
        _imageId = updated.id;
        _imageUrl = updated.imageUrl;
        _editingBytes = null;
        _hasEdited = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCreating ? 'Sketch created.' : 'Sketch updated.'),
        ),
      );
      UserActivityLogger.instance.record(
        operation: isCreating ? 'sketch_create' : 'sketch_edit',
        status: 'succeeded',
        targetType: 'sketch',
        targetId: newImageId,
        parentImageId: parentId,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      if (isCreating && mounted) {
        // Return the newly created sketch to the reference details page so it
        // can add it to Associated Images immediately.
        _finishImageWindow();
      }
    } catch (error) {
      final alreadyAttached = isCreating && _isAlreadyAttachedError(error);
      UserActivityLogger.instance.record(
        operation: isCreating ? 'sketch_create' : 'sketch_edit',
        status: alreadyAttached ? 'succeeded' : 'failed',
        targetType: 'sketch',
        targetId: oldImageId,
        parentImageId: parentId,
        durationMs: stopwatch.elapsedMilliseconds,
        error: error,
      );
      if (mounted) {
        if (alreadyAttached) {
          setState(() => _editingBytes = null);
        } else if (isCreating) {
          setState(() => _hasSavedSketchForThisWindow = false);
        }
        final message = alreadyAttached
            ? 'This sketch is already attached to the reference.'
            : error is TimeoutException
            ? 'The sketch save timed out. Check your connection and try again.'
            : 'Unable to update the sketch: $error';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isApplyingEdit = false);
    }
  }

  void _finishImageWindow() {
    final imageId = _imageId;
    final result = _hasEdited && imageId != null
        ? _EditedSketch(
            imageId: imageId,
            imageUrl: _imageUrl,
            replacesCurrentImage: widget.createSketchParentImageId == null,
          )
        : null;
    if (_hasEdited && !_allowPop) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_hasEdited,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finishImageWindow();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: BackButton(onPressed: _finishImageWindow),
          title: Text(_editingBytes == null ? 'Image' : 'Edit sketch'),
          actions: [
            HomeButton(enabled: !_isApplyingEdit && !_isEditorProcessing),
            if (_editingBytes != null) ...[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _isApplyingEdit
                    ? null
                    : () => setState(() => _editingBytes = null),
                child: const Text('Cancel'),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _imageAdjustmentController.hasChanges,
                builder: (context, hasChanges, _) => TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                  ),
                  onPressed:
                      _isApplyingEdit ||
                          (!hasChanges &&
                              widget.createSketchParentImageId == null)
                      ? null
                      : _imageAdjustmentController.apply,
                  child: _isEditorProcessing || _isApplyingEdit
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ] else ...[
              if (_imageId != null) ...[
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
          ],
        ),
        body: _editingBytes != null
            ? Stack(
                children: [
                  Positioned.fill(
                    child: ImageAdjustmentScreen(
                      imageBytes: _editingBytes!,
                      embedded: true,
                      onDone: _applyEditedSketch,
                      onEditWithAi: _openAiEditor,
                      onProcessingChanged: (processing) {
                        if (mounted) {
                          setState(() {
                            _isEditorProcessing = processing;
                            if (processing && !_isApplyingEdit) {
                              _saveProgressLabel = 'Processing image…';
                            }
                          });
                        }
                      },
                      controller: _imageAdjustmentController,
                    ),
                  ),
                  if (_isLoadingEditor ||
                      _isEditorProcessing ||
                      _isApplyingEdit)
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0x99000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isLoadingEditor &&
                                        !_isEditorProcessing &&
                                        !_isApplyingEdit
                                    ? 'Preparing sketch…'
                                    : _saveProgressLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
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
                                  _imageUrl,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }

                                        final expectedBytes =
                                            loadingProgress.expectedTotalBytes;

                                        final value = expectedBytes == null
                                            ? null
                                            : loadingProgress
                                                      .cumulativeBytesLoaded /
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
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
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
                    if (widget.editableParentImageId != null ||
                        widget.createSketchParentImageId != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Center(
                          child: widget.createSketchParentImageId != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isLoadingEditor
                                          ? null
                                          : _startEditing,
                                      icon: const Icon(Icons.crop_rotate),
                                      label: const Text('Edit sketch'),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _isLoadingEditor
                                          ? null
                                          : _saveUnchangedSketch,
                                      icon: _isLoadingEditor
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.add_photo_alternate,
                                            ),
                                      label: const Text('Save as sketch'),
                                    ),
                                  ],
                                )
                              : FilledButton.icon(
                                  onPressed: _isLoadingEditor
                                      ? null
                                      : _startEditing,
                                  icon: const Icon(Icons.crop_rotate),
                                  label: const Text('Edit sketch'),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
