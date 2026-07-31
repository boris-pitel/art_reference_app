import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/image_asset_service.dart';
import '../services/keyword_service.dart';
import 'image_details_screen.dart';

class KeywordSearchScreen extends StatefulWidget {
  const KeywordSearchScreen({
    super.key,
    required this.categories,
  });

  final List<ReferenceCategory> categories;

  @override
  State<KeywordSearchScreen> createState() => _KeywordSearchScreenState();
}

class _KeywordSearchResult {
  const _KeywordSearchResult({
    required this.image,
    required this.matchingKeywords,
  });

  final ImageAssetInfo image;
  final List<String> matchingKeywords;
}

class _KeywordSearchScreenState extends State<KeywordSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final KeywordService _keywordService;
  late final ImageAssetService _imageAssetService;

  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;
  String _lastQuery = '';

  List<_KeywordSearchResult> _results = const <_KeywordSearchResult>[];

  @override
  void initState() {
    super.initState();

    final supabase = Supabase.instance.client;

    _keywordService = KeywordService(supabase);
    _imageAssetService = ImageAssetService(supabase);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_isSearching) {
      return;
    }

    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _lastQuery = '';
        _results = const <_KeywordSearchResult>[];
        _errorMessage = null;
      });

      _searchFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _lastQuery = query;
      _results = const <_KeywordSearchResult>[];
      _errorMessage = null;
    });

    try {
      final matchingKeywordRows = await _keywordService.searchKeywords(query);

      if (matchingKeywordRows.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isSearching = false;
        });

        return;
      }

      final keywordsByImageId = <String, Set<String>>{};

      for (final row in matchingKeywordRows) {
        keywordsByImageId
            .putIfAbsent(row.imageId, () => <String>{})
            .add(row.keyword);
      }

      final categoryImageLists = await Future.wait(
        widget.categories.map(_imageAssetService.listImages),
      );

      final imagesById = <String, ImageAssetInfo>{};

      for (final images in categoryImageLists) {
        for (final image in images) {
          imagesById.putIfAbsent(image.id, () => image);
        }
      }

      final results = <_KeywordSearchResult>[];

      for (final entry in keywordsByImageId.entries) {
        final image = imagesById[entry.key];

        if (image == null) {
          continue;
        }

        final matchingKeywords = entry.value.toList()
          ..sort(
            (left, right) =>
                left.toLowerCase().compareTo(right.toLowerCase()),
          );

        results.add(
          _KeywordSearchResult(
            image: image,
            matchingKeywords: matchingKeywords,
          ),
        );
      }

      results.sort(
        (left, right) =>
            right.image.dateAdded.compareTo(left.image.dateAdded),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSearching = false;
        _errorMessage = 'Unable to search keywords.\n$error';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _hasSearched = false;
      _lastQuery = '';
      _results = const <_KeywordSearchResult>[];
      _errorMessage = null;
    });

    _searchFocusNode.requestFocus();
  }

  Future<void> _openImage(ImageAssetInfo image) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return ImageDetailsScreen(
            imageId: image.id,
            imageUrl: image.imageUrl,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Keywords'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    enabled: !_isSearching,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Keyword',
                      hintText: 'For example, portrait or light',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _isSearching ? null : _clearSearch,
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear',
                            ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                    onSubmitted: (_) {
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.3),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isSearching ? 'Searching...' : 'Search'),
                ),
              ],
            ),
          ),
          if (_isSearching) const LinearProgressIndicator(),
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isSearching ? null : _search,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sell_outlined, size: 58),
              SizedBox(height: 16),
              Text(
                'Search your reference images by keyword.',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Partial words work too. Searching for "light" '
                'will find "dramatic light".',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Searching your image library...'),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined, size: 58),
              const SizedBox(height: 16),
              Text(
                'No images found for “$_lastQuery”.',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Try a shorter word or another keyword.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columnCount = width >= 1100
            ? 5
            : width >= 850
                ? 4
                : width >= 600
                    ? 3
                    : 2;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: _results.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            return _buildResultCard(context, _results[index]);
          },
        );
      },
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    _KeywordSearchResult result,
  ) {
    final image = result.image;
    final displayUrl = image.thumbnailUrl ?? image.imageUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openImage(image);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                displayUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 42,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: result.matchingKeywords
                    .map(
                      (keyword) => Chip(
                        label: Text(keyword),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
