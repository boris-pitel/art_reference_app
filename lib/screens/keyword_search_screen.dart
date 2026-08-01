import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/image_search_service.dart';
import 'image_details_screen.dart';

class KeywordSearchScreen extends StatefulWidget {
  const KeywordSearchScreen({super.key, required this.categories});

  final List<ReferenceCategory> categories;

  @override
  State<KeywordSearchScreen> createState() => _KeywordSearchScreenState();
}

class _KeywordSearchScreenState extends State<KeywordSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ImageSearchService _searchService;

  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;
  String _lastQuery = '';
  List<ImageSearchResult> _results = const <ImageSearchResult>[];

  @override
  void initState() {
    super.initState();
    _searchService = ImageSearchService(Supabase.instance.client);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_isSearching) return;

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _lastQuery = '';
        _results = const <ImageSearchResult>[];
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
      _results = const <ImageSearchResult>[];
      _errorMessage = null;
    });

    try {
      final results = await _searchService.searchImages(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Unable to search references.\n$error';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _hasSearched = false;
      _lastQuery = '';
      _results = const <ImageSearchResult>[];
      _errorMessage = null;
    });
    _searchFocusNode.requestFocus();
  }

  Future<void> _openImage(ImageSearchResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            ImageDetailsScreen(imageId: result.id, imageUrl: result.imageUrl),
      ),
    );

    if (mounted && _lastQuery.isNotEmpty) await _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search References')),
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
                      labelText: 'Search',
                      hintText: 'Keyword, title, or notes',
                      helperText: 'Searches saved keywords, titles, and notes.',
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
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _search(),
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
          Expanded(child: _buildBody(context)),
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
              Text(_errorMessage!, textAlign: TextAlign.center),
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
              Icon(Icons.manage_search_outlined, size: 58),
              SizedBox(height: 16),
              Text(
                'Search your reference library.',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Search checks saved keywords, image titles, and notes. '
                'Partial words work too.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: Text('Searching your image library...'));
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
              const Text('Try a shorter word or another search term.'),
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
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, index) =>
              _buildResultCard(context, _results[index]),
        );
      },
    );
  }

  Widget _buildResultCard(BuildContext context, ImageSearchResult result) {
    final displayUrl = result.thumbnailUrl ?? result.imageUrl;
    final title = result.title ?? 'Untitled reference';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openImage(result),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                displayUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 42),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...result.matchedIn.map(
                    (source) => Chip(
                      avatar: Icon(_matchIcon(source), size: 17),
                      label: Text(source),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ...result.matchingKeywords.map(
                    (keyword) => Chip(
                      label: Text(keyword),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _matchIcon(String source) {
    switch (source) {
      case 'Title':
        return Icons.title;
      case 'Notes':
        return Icons.notes_outlined;
      case 'Keyword':
        return Icons.sell_outlined;
      default:
        return Icons.search;
    }
  }
}
