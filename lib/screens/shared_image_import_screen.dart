import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/category_service.dart';
import '../services/image_asset_service.dart';
import 'category_screen.dart';

class SharedImageImportScreen extends StatefulWidget {
  const SharedImageImportScreen({required this.sharedImagePath, super.key});

  final String sharedImagePath;

  @override
  State<SharedImageImportScreen> createState() =>
      _SharedImageImportScreenState();
}

class _SharedImageImportScreenState extends State<SharedImageImportScreen> {
  late final ImageAssetService _imageAssetService;
  late final CategoryService _categoryService;

  List<ReferenceCategory> _categories = const <ReferenceCategory>[];

  Uint8List? _imageBytes;
  String? _errorMessage;
  String? _categoryErrorMessage;

  bool _isReadingImage = true;
  bool _isLoadingCategories = true;
  bool _isUploading = false;

  ReferenceCategory? _selectedCategory;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();

    final supabase = Supabase.instance.client;

    _imageAssetService = ImageAssetService(supabase);
    _categoryService = CategoryService(supabase);

    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await Future.wait<void>([_readSharedImage(), _loadCategories()]);
  }

  Future<void> _readSharedImage() async {
    if (mounted) {
      setState(() {
        _isReadingImage = true;
        _errorMessage = null;
      });
    }

    try {
      final normalizedPath = widget.sharedImagePath.trim();

      if (normalizedPath.isEmpty) {
        throw StateError('Android did not provide a valid image path.');
      }

      final sharedFile = XFile(normalizedPath);
      final bytes = await sharedFile.readAsBytes();

      if (bytes.isEmpty) {
        throw StateError('The shared image is empty.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _imageBytes = bytes;
        _isReadingImage = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isReadingImage = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadCategories() async {
    if (mounted) {
      setState(() {
        _isLoadingCategories = true;
        _categoryErrorMessage = null;
      });
    }

    try {
      final categories = await _categoryService.listCategories();

      if (!mounted) {
        return;
      }

      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        _categoryErrorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to load categories for shared image: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCategories = false;
        _categoryErrorMessage = error.toString();
      });
    }
  }

  Future<void> _importIntoCategory(ReferenceCategory category) async {
    if (_isUploading) {
      return;
    }

    final bytes = _imageBytes;

    if (bytes == null || bytes.isEmpty) {
      _showMessage('The shared image is not available.');
      return;
    }

    setState(() {
      _isUploading = true;
      _selectedCategory = category;
      _uploadStatus = 'Preparing thumbnail...';
    });

    try {
      setState(() {
        _uploadStatus = 'Saving to ${category.displayName}...';
      });

      await _imageAssetService.uploadImage(bytes, category);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Photo reference saved to '
        '${category.displayName}.',
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (!mounted) {
        return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) {
            return CategoryScreen(category: category);
          },
        ),
      );
    } on FunctionException catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.status == 409
          ? 'This photo is already in '
                '${category.displayName}.'
          : 'Unable to save the photo: '
                '${error.details}';

      _showMessage(message);
    } on UnsupportedImageFormatException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.toString());
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save the shared photo: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _selectedCategory = null;
          _uploadStatus = '';
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isUploading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import Reference'),
          automaticallyImplyLeading: !_isUploading,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody()),
            if (_isUploading) Positioned.fill(child: _buildUploadOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isReadingImage) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading shared image...'),
          ],
        ),
      );
    }

    final errorMessage = _errorMessage;

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52),
              const SizedBox(height: 16),
              const Text(
                'Unable to open the shared image.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _readSharedImage,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final bytes = _imageBytes;

    if (bytes == null) {
      return const Center(child: Text('No shared image was received.'));
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 220,
                  maxHeight: 420,
                ),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 260,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined, size: 52),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Choose a category',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'The reference will be imported '
              'directly into this collection.',
            ),
          ),
        ),
        _buildCategorySection(),
      ],
    );
  }

  Widget _buildCategorySection() {
    if (_isLoadingCategories) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Loading categories...'),
              ],
            ),
          ),
        ),
      );
    }

    final categoryErrorMessage = _categoryErrorMessage;

    if (categoryErrorMessage != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              const Text(
                'Unable to load categories.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(categoryErrorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadCategories,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: Text('No categories are available.')),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      sliver: SliverGrid.builder(
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
        ),
        itemBuilder: (context, index) {
          final category = _categories[index];

          return _CategoryChoiceCard(
            category: category,
            enabled: !_isUploading,
            selected: _selectedCategory == category,
            onPressed: () {
              _importIntoCategory(category);
            },
          );
        },
      ),
    );
  }

  Widget _buildUploadOverlay() {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _uploadStatus.isEmpty
                        ? 'Saving reference...'
                        : _uploadStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The same thumbnail, duplicate '
                    'check, and upload process is '
                    'being used.',
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
}

class _CategoryChoiceCard extends StatelessWidget {
  const _CategoryChoiceCard({
    required this.category,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final ReferenceCategory category;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final thumbnailAsset = category.thumbnailAsset?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailAsset != null && thumbnailAsset.isNotEmpty)
              Image.asset(
                thumbnailAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const _CategoryPlaceholder();
                },
              )
            else
              const _CategoryPlaceholder(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.3, 1],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                category.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const ColoredBox(
                color: Colors.black38,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.collections_bookmark_outlined,
          size: 44,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
