import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/image_asset_service.dart';
import '../services/image_print_service.dart';
import 'help_screen.dart';
import 'image_details_screen.dart';

class _LoadedImage {
  const _LoadedImage({
    required this.id,
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  final String id;
  final String imageUrl;
  final String? thumbnailUrl;
}

class _DownloadedImage {
  const _DownloadedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  String get extension {
    if (mimeType == 'image/png') {
      return 'png';
    }

    return 'jpg';
  }
}

enum _ImageAction { share, save, print, remove }

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final ReferenceCategory category;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  late final ImageAssetService _imageAssetService;

  final List<_LoadedImage> _images = [];

  bool _isLoading = true;
  bool _isUploading = false;

  String _uploadStatus = '';

  String? _openingImageId;
  String? _removingImageId;
  String? _sharingImageId;
  String? _savingImageId;
  String? _printingImageId;
  String? _errorMessage;

  bool get _isBusy {
    return _isUploading ||
        _openingImageId != null ||
        _removingImageId != null ||
        _sharingImageId != null ||
        _savingImageId != null ||
        _printingImageId != null;
  }

  bool get _cameraIsAvailable {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();

    _imageAssetService = ImageAssetService(Supabase.instance.client);

    _loadImages();
  }

  Future<List<_LoadedImage>> _fetchImages() async {
    final imageInfoList = await _imageAssetService.listImages(widget.category);

    return imageInfoList
        .map(
          (imageInfo) => _LoadedImage(
            id: imageInfo.id,
            imageUrl: imageInfo.imageUrl,
            thumbnailUrl: imageInfo.thumbnailUrl,
          ),
        )
        .toList();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loadedImages = await _fetchImages();

      if (!mounted) {
        return;
      }

      setState(() {
        _images
          ..clear()
          ..addAll(loadedImages);

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _refreshUntilImageAppears(String expectedImageId) async {
    const maximumAttempts = 8;
    const delayBetweenAttempts = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
      final loadedImages = await _fetchImages();

      final imageIsVisible = loadedImages.any(
        (image) => image.id == expectedImageId,
      );

      if (imageIsVisible || attempt == maximumAttempts) {
        if (!mounted) {
          return;
        }

        setState(() {
          _images
            ..clear()
            ..addAll(loadedImages);

          _isLoading = false;
          _errorMessage = null;
        });

        return;
      }

      await Future<void>.delayed(delayBetweenAttempts);
    }
  }

  void _setUploadStatus(String status) {
    if (!mounted) {
      return;
    }

    setState(() {
      _uploadStatus = status;
    });
  }

  Future<void> _openHelp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => const HelpScreen()));
  }

  Future<void> _addPhotoReference(ImageSource source) async {
    if (_isBusy) {
      return;
    }

    final sourceDescription = source == ImageSource.camera
        ? 'Opening camera...'
        : 'Opening photo library...';

    setState(() {
      _isUploading = true;
      _uploadStatus = sourceDescription;
    });

    try {
      final selectedImage = await _imagePicker.pickImage(source: source);

      if (selectedImage == null) {
        return;
      }

      _setUploadStatus(
        source == ImageSource.camera
            ? 'Reading captured photo...'
            : 'Reading selected photo...',
      );

      final bytes = await selectedImage.readAsBytes();

      if (!mounted) {
        return;
      }

      _setUploadStatus('Preparing thumbnail and uploading photo...');

      final imageId = await _imageAssetService.uploadImage(
        bytes,
        widget.category,
      );

      if (!mounted) {
        return;
      }

      _setUploadStatus('Updating ${widget.category.displayName}...');

      await _refreshUntilImageAppears(imageId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo reference saved.')));
    } on FunctionException catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.status == 409
          ? 'This photo is already in this category.'
          : 'Unable to save the photo: ${error.details}';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save the photo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
      }
    }
  }

  Future<void> _openImageDetails(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _openingImageId = image.id;
    });

    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => ImageDetailsScreen(
            imageId: image.id,
            imageUrl: image.imageUrl,
            navigationItems: _images
                .map(
                  (item) => ImageDetailsNavigationItem(
                    imageId: item.id,
                    imageUrl: item.imageUrl,
                  ),
                )
                .toList(growable: false),
            navigationIndex: _images.indexWhere((item) => item.id == image.id),
          ),
        ),
      );

      if (changed == true && mounted) {
        await _loadImages();
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingImageId = null;
        });
      }
    }
  }

  Future<_DownloadedImage> _downloadImage(_LoadedImage image) async {
    final response = await http.get(Uri.parse(image.imageUrl));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Image download failed with status ${response.statusCode}.',
      );
    }

    final bytes = response.bodyBytes;

    if (bytes.isEmpty) {
      throw StateError('The downloaded image is empty.');
    }

    return _DownloadedImage(
      bytes: bytes,
      mimeType: _detectMimeType(response.headers['content-type'], bytes),
    );
  }

  Future<void> _shareImage(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _sharingImageId = image.id;
    });

    try {
      final downloadedImage = await _downloadImage(image);

      Rect? sharePositionOrigin;

      final renderObject = context.findRenderObject();

      if (renderObject is RenderBox && renderObject.hasSize) {
        final topLeft = renderObject.localToGlobal(Offset.zero);

        sharePositionOrigin = topLeft & renderObject.size;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              downloadedImage.bytes,
              mimeType: downloadedImage.mimeType,
              name: 'art_reference_${image.id}.${downloadedImage.extension}',
            ),
          ],
          subject: 'Painter Reference',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share the reference: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharingImageId = null;
        });
      }
    }
  }

  Future<void> _saveImageToPhotos(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    if (kIsWeb) {
      _showMessage('Save to Photos is available in the phone app.');
      return;
    }

    setState(() {
      _savingImageId = image.id;
    });

    try {
      final downloadedImage = await _downloadImage(image);

      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        throw StateError('Permission to save images was not granted.');
      }

      await Gal.putImageBytes(downloadedImage.bytes);

      if (!mounted) {
        return;
      }

      _showMessage('Reference saved to Photos.');
    } on GalException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save the reference: ${error.type.message}');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save the reference: $error');
    } finally {
      if (mounted) {
        setState(() {
          _savingImageId = null;
        });
      }
    }
  }

  Future<void> _printImage(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _printingImageId = image.id;
    });

    try {
      final downloadedImage = await _downloadImage(image);

      await ImagePrintService.printImage(
        imageBytes: downloadedImage.bytes,
        documentName: 'Painter Reference ${image.id}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to print the reference: $error');
    } finally {
      if (mounted) {
        setState(() {
          _printingImageId = null;
        });
      }
    }
  }

  String _detectMimeType(String? responseContentType, Uint8List bytes) {
    final normalizedHeader = responseContentType
        ?.split(';')
        .first
        .trim()
        .toLowerCase();

    if (normalizedHeader == 'image/jpeg' || normalizedHeader == 'image/png') {
      return normalizedHeader!;
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }

    return 'image/jpeg';
  }

  Future<void> _removeFromCategory(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _removingImageId = image.id;
    });

    try {
      await _imageAssetService.removeImageFromCategory(
        image.id,
        widget.category,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _images.removeWhere((existingImage) => existingImage.id == image.id);

        _removingImageId = null;
      });

      _showMessage('Reference removed.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _removingImageId = null;
      });

      _showMessage('Unable to remove reference: $error');
    }
  }

  Future<void> _handleImageAction(
    _ImageAction action,
    _LoadedImage image,
  ) async {
    switch (action) {
      case _ImageAction.share:
        await _shareImage(image);
        return;

      case _ImageAction.save:
        await _saveImageToPhotos(image);
        return;

      case _ImageAction.print:
        await _printImage(image);
        return;

      case _ImageAction.remove:
        await _removeFromCategory(image);
        return;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showMobileActions(_LoadedImage image) async {
    if (_isBusy) {
      return;
    }

    final action = await showModalBottomSheet<_ImageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Reference',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_ImageAction.share);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Save to Photos'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_ImageAction.save);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print'),
                onTap: () {
                  Navigator.of(sheetContext).pop(_ImageAction.print);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Remove',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop(_ImageAction.remove);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (action != null && mounted) {
      await _handleImageAction(action, image);
    }
  }

  Future<void> _showDesktopActions(
    _LoadedImage image,
    Offset globalPosition,
  ) async {
    if (_isBusy) {
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject();

    if (overlay is! RenderBox) {
      return;
    }

    final action = await showMenu<_ImageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: _ImageAction.share,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.ios_share_outlined),
            title: Text('Share'),
          ),
        ),
        const PopupMenuItem(
          value: _ImageAction.save,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_library_outlined),
            title: Text('Save to Photos'),
          ),
        ),
        const PopupMenuItem(
          value: _ImageAction.print,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.print_outlined),
            title: Text('Print'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ImageAction.remove,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );

    if (action != null && mounted) {
      await _handleImageAction(action, image);
    }
  }

  Future<void> _handleLongPress(_LoadedImage image) async {
    await HapticFeedback.selectionClick();

    if (!mounted) {
      return;
    }

    await _showMobileActions(image);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.displayName),
        actions: [
          IconButton(
            onPressed: _openHelp,
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help and About',
          ),
          IconButton(
            onPressed: _isLoading || _isBusy ? null : _loadImages,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          if (_isUploading) Positioned.fill(child: _buildUploadOverlay()),
        ],
      ),
      floatingActionButton: _buildAddButtons(),
    );
  }

  Widget _buildAddButtons() {
    if (!_cameraIsAvailable) {
      return FloatingActionButton.extended(
        heroTag: 'galleryButton',
        onPressed: _isBusy
            ? null
            : () => _addPhotoReference(ImageSource.gallery),
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_isUploading ? 'Working...' : 'Gallery'),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'galleryButton',
          onPressed: _isBusy
              ? null
              : () => _addPhotoReference(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Gallery'),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'cameraButton',
          onPressed: _isBusy
              ? null
              : () => _addPhotoReference(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Camera'),
        ),
      ],
    );
  }

  Widget _buildUploadOverlay() {
    return ColoredBox(
      color: Colors.black45,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _uploadStatus.isEmpty ? 'Working...' : _uploadStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Large photographs may take a little while.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Unable to load photo references.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadImages,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_images.isEmpty) {
      return const Center(
        child: Text('No photo references yet.', style: TextStyle(fontSize: 20)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _images.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final image = _images[index];

        final isOpening = _openingImageId == image.id;
        final isRemoving = _removingImageId == image.id;
        final isSharing = _sharingImageId == image.id;
        final isSaving = _savingImageId == image.id;
        final isPrinting = _printingImageId == image.id;

        final isWorking =
            isOpening || isRemoving || isSharing || isSaving || isPrinting;

        return GestureDetector(
          onLongPress: isWorking ? null : () => _handleLongPress(image),
          onSecondaryTapDown: isWorking
              ? null
              : (details) => _showDesktopActions(image, details.globalPosition),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isWorking ? null : () => _openImageDetails(image),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(image),
                  if (isWorking)
                    Container(
                      color: Colors.black38,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              isRemoving
                                  ? 'Removing...'
                                  : isSharing
                                  ? 'Preparing...'
                                  : isSaving
                                  ? 'Saving...'
                                  : isPrinting
                                  ? 'Preparing print...'
                                  : 'Opening...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(_LoadedImage image) {
    final thumbnailUrl = image.thumbnailUrl;

    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      return _buildThumbnailPlaceholder();
    }

    return Image.network(
      thumbnailUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildThumbnailPlaceholder();
      },
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 44,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
