import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/image_asset_service.dart';

enum _AssociatedImageAction { open, delete }

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

class _ImageDetailsScreenState extends State<ImageDetailsScreen> {
  static const String _userEmail = 'borispitel1@gmail.com';

  final TextEditingController _titleController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _sourceUrlController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  final Set<String> _deletingAssociatedImageIds = <String>{};

  bool _isLoadingMetadata = true;
  bool _isSavingMetadata = false;
  bool _isFavorite = false;

  bool _isLoadingAssociatedImages = true;
  bool _isUploadingAssociatedImage = false;

  String? _metadataError;
  String? _associatedImagesError;

  List<ImageAssetInfo> _associatedImages = [];

  SupabaseClient get _supabase => Supabase.instance.client;

  ImageAssetService get _imageAssetService => ImageAssetService(_supabase);

  String get _userId {
    final normalizedEmail = _userEmail.trim().toLowerCase();

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

  @override
  void initState() {
    super.initState();

    _loadMetadata();
    _loadAssociatedImages();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _sourceUrlController.dispose();

    super.dispose();
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoadingMetadata = true;
      _metadataError = null;
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
          'get-image-metadata returned an '
          'unexpected response: $data',
        );
      }

      if (data['error'] != null) {
        throw StateError(data['error'].toString());
      }

      if (!mounted) {
        return;
      }

      _titleController.text = data['title'] as String? ?? '';

      _notesController.text = data['notes'] as String? ?? '';

      _sourceUrlController.text = data['source_url'] as String? ?? '';

      setState(() {
        _isFavorite = data['is_favorite'] == true;

        _isLoadingMetadata = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingMetadata = false;

        _metadataError = 'Unable to load image details.\n$error';
      });
    }
  }

  Future<void> _saveMetadata() async {
    if (_isSavingMetadata) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSavingMetadata = true;
      _metadataError = null;
    });

    try {
      final response = await _supabase.functions.invoke(
        'save-image-metadata',
        body: {
          'user_id': _userId,
          'image_id': widget.imageId,
          'title': _normalizedNullableText(_titleController.text),
          'notes': _normalizedNullableText(_notesController.text),
          'source_url': _normalizedNullableText(_sourceUrlController.text),
          'is_favorite': _isFavorite,
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw StateError(
          'save-image-metadata returned an '
          'unexpected response: $data',
        );
      }

      if (data['saved'] != true) {
        throw StateError(
          data['error']?.toString() ?? 'The metadata was not saved.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingMetadata = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image details saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingMetadata = false;

        _metadataError = 'Unable to save image details.\n$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save image details.')),
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
        _associatedImagesError =
            'Unable to load associated images.\n'
            '$error';
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
        _associatedImagesError =
            'Unable to add the associated image.\n'
            '$error';
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

      case _AssociatedImageAction.delete:
        await _confirmAndRemoveAssociatedImage(image);
    }
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
            'Unable to delete the associated '
            'image.\n$error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete the associated image.')),
      );
    }
  }

  void _openAssociatedImage(ImageAssetInfo image) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.sizeOf(dialogContext).height * 0.9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 6,
                      child: Center(
                        child: Image.network(
                          image.imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }

                            final expectedBytes =
                                loadingProgress.expectedTotalBytes;

                            final value = expectedBytes == null
                                ? null
                                : loadingProgress.cumulativeBytesLoaded /
                                      expectedBytes;

                            return Center(
                              child: CircularProgressIndicator(value: value),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.broken_image_outlined,
                                    size: 56,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 12),
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
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    return Scaffold(
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
                  },
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
          ),
          IconButton(
            onPressed: _isLoadingMetadata || _isSavingMetadata
                ? null
                : _saveMetadata,
            icon: _isSavingMetadata
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.save_outlined),
            tooltip: 'Save',
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
              _buildAssociatedImagesSection(context),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImageViewer(BuildContext context, double imageHeight) {
    return Container(
      width: double.infinity,
      height: imageHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
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
                        'Unable to load the '
                        'full image.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _metadataError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
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
                  'Add composition ideas, '
                  'color notes, or painting plans',
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
            controller: _sourceUrlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Source URL',
              hintText: 'https://example.com/reference',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Favorite'),
            subtitle: const Text(
              'Mark this image as an '
              'important reference',
            ),
            value: _isFavorite,
            onChanged: _isSavingMetadata
                ? null
                : (value) {
                    setState(() {
                      _isFavorite = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSavingMetadata ? null : _saveMetadata,
              icon: _isSavingMetadata
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSavingMetadata ? 'Saving...' : 'Save Details'),
            ),
          ),
        ],
      ],
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
              label: const Text('Gallery'),
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
          Container(
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
                  _associatedImagesError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoadingAssociatedImages
                      ? null
                      : _loadAssociatedImages,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
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
                  'Use Gallery or Camera to '
                  'add the first one.',
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

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isDeleting
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
                  enabled: !isDeleting,
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
            if (!isDeleting)
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
            if (isDeleting)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
