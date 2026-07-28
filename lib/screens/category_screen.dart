import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/image_asset_service.dart';
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
  String? _errorMessage;

  bool get _isBusy {
    return _isUploading || _openingImageId != null || _removingImageId != null;
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

  Future<void> _addPhotoReference() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Opening photo library...';
    });

    try {
      final selectedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (selectedImage == null) {
        return;
      }

      _setUploadStatus('Reading selected photo...');

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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ImageDetailsScreen(imageId: image.id, imageUrl: image.imageUrl),
      ),
    );

    if (mounted) {
      setState(() {
        _openingImageId = null;
      });
    }
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reference removed.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _removingImageId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove reference: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.displayName),
        actions: [
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _addPhotoReference,
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_isUploading ? 'Working...' : 'Add Photo Reference'),
      ),
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

        return Material(
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isOpening || isRemoving
                ? null
                : () => _openImageDetails(image),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(image),
                Positioned(
                  top: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: isOpening || isRemoving
                          ? null
                          : () => _removeFromCategory(image),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.white,
                      ),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      splashRadius: 18,
                      tooltip: 'Remove reference',
                    ),
                  ),
                ),
                if (isOpening || isRemoving)
                  Container(
                    color: Colors.black38,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            isRemoving ? 'Removing...' : 'Opening...',
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
