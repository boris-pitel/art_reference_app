import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  bool _isLoadingMetadata = true;
  bool _isSavingMetadata = false;
  bool _isFavorite = false;

  String? _metadataError;

  SupabaseClient get _supabase => Supabase.instance.client;

  String get _userId {
    final normalizedEmail = _userEmail.trim().toLowerCase();

    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$normalizedEmail',
    );
  }

  @override
  void initState() {
    super.initState();

    _loadMetadata();
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
        const Text(
          'Associated Images',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
              Text('No associated images yet.', style: TextStyle(fontSize: 17)),
            ],
          ),
        ),
      ],
    );
  }
}
