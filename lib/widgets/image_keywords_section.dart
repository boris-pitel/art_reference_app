import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/keyword_service.dart';

class ImageKeywordsSection extends StatefulWidget {
  const ImageKeywordsSection({
    super.key,
    required this.imageId,
    this.onKeywordsChanged,
  });

  final String imageId;
  final ValueChanged<List<String>>? onKeywordsChanged;

  @override
  State<ImageKeywordsSection> createState() => ImageKeywordsSectionState();
}

class ImageKeywordsSectionState extends State<ImageKeywordsSection> {
  final TextEditingController _keywordController = TextEditingController();

  final FocusNode _keywordFocusNode = FocusNode();

  late final KeywordService _keywordService;

  List<ImageKeyword> _keywords = [];

  final Set<int> _deletingKeywordIds = <int>{};

  bool _isLoading = true;
  bool _isAdding = false;

  String? _errorMessage;

  void _notifyKeywordsChanged() {
    widget.onKeywordsChanged?.call(
      _keywords.map((keyword) => keyword.keyword).toList(growable: false),
    );
  }

  bool containsKeyword(String keyword) {
    final normalized = keyword.trim().toLowerCase();

    return _keywords.any(
      (existingKeyword) =>
          existingKeyword.keyword.trim().toLowerCase() == normalized,
    );
  }

  Future<bool> addKeywordFromSuggestion(String keyword) async {
    final normalizedKeyword = keyword.trim();

    if (normalizedKeyword.isEmpty || _isAdding) {
      return false;
    }

    if (containsKeyword(normalizedKeyword)) {
      return false;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final addedKeyword = await _keywordService.addKeyword(
        imageId: widget.imageId,
        keyword: normalizedKeyword,
      );

      if (!mounted) {
        return false;
      }

      setState(() {
        _keywords = [..._keywords, addedKeyword]
          ..sort(
            (left, right) => left.keyword.toLowerCase().compareTo(
              right.keyword.toLowerCase(),
            ),
          );
      });

      _notifyKeywordsChanged();
      return true;
    } on DuplicateKeywordException {
      if (!mounted) {
        return false;
      }

      await _loadKeywords();
      return false;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      setState(() {
        _errorMessage = 'Unable to add the keyword.\n$error';
      });

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _keywordService = KeywordService(Supabase.instance.client);

    _loadKeywords();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _keywordFocusNode.dispose();

    super.dispose();
  }

  Future<void> reloadKeywords() async {
    await _loadKeywords();
  }

  Future<void> _loadKeywords() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final keywords = await _keywordService.listKeywords(widget.imageId);

      if (!mounted) {
        return;
      }

      setState(() {
        _keywords = List<ImageKeyword>.of(keywords);
        _isLoading = false;
      });

      _notifyKeywordsChanged();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load keywords.\n$error';
      });
    }
  }

  Future<void> _addKeyword() async {
    if (_isAdding) {
      return;
    }

    final keyword = _keywordController.text.trim();

    if (keyword.isEmpty) {
      _keywordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final addedKeyword = await _keywordService.addKeyword(
        imageId: widget.imageId,
        keyword: keyword,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _keywords = [..._keywords, addedKeyword]
          ..sort(
            (left, right) => left.keyword.toLowerCase().compareTo(
              right.keyword.toLowerCase(),
            ),
          );

        _isAdding = false;
      });

      _keywordController.clear();
      _keywordFocusNode.requestFocus();
      _notifyKeywordsChanged();
    } on DuplicateKeywordException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAdding = false;
        _errorMessage = error.toString();
      });

      _keywordFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAdding = false;
        _errorMessage = 'Unable to add the keyword.\n$error';
      });
    }
  }

  Future<void> _deleteKeyword(ImageKeyword keyword) async {
    if (_deletingKeywordIds.contains(keyword.id)) {
      return;
    }

    setState(() {
      _deletingKeywordIds.add(keyword.id);
      _errorMessage = null;
    });

    try {
      await _keywordService.deleteKeyword(keyword);

      if (!mounted) {
        return;
      }

      setState(() {
        _keywords.removeWhere(
          (existingKeyword) => existingKeyword.id == keyword.id,
        );

        _deletingKeywordIds.remove(keyword.id);
      });

      _notifyKeywordsChanged();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deletingKeywordIds.remove(keyword.id);
        _errorMessage = 'Unable to remove "${keyword.keyword}".\n$error';
      });
    }
  }

  Widget _buildErrorMessage(BuildContext context) {
    final errorMessage = _errorMessage;

    if (errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        errorMessage,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.sell_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Keywords',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Add words or short phrases that describe '
          'the subject, mood, colors, lighting, or '
          'painting ideas.',
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _keywordController,
                focusNode: _keywordFocusNode,
                enabled: !_isAdding,
                maxLength: 100,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'New keyword',
                  hintText: 'For example, dramatic light',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.add_circle_outline),
                ),
                onSubmitted: (_) {
                  _addKeyword();
                },
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.icon(
                onPressed: _isAdding ? null : _addKeyword,
                icon: _isAdding
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
                      )
                    : const Icon(Icons.add),
                label: Text(_isAdding ? 'Adding...' : 'Add'),
              ),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorMessage(context),
        ],
        const SizedBox(height: 12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading keywords...'),
                ],
              ),
            ),
          )
        else if (_keywords.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.label_outline, size: 38),
                SizedBox(height: 10),
                Text(
                  'No keywords yet.',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 5),
                Text(
                  'Add the first keyword above.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _keywords
                .map((keyword) {
                  final isDeleting = _deletingKeywordIds.contains(keyword.id);

                  return InputChip(
                    label: Text(keyword.keyword),
                    avatar: isDeleting
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.label_outline, size: 18),
                    onDeleted: isDeleting
                        ? null
                        : () {
                            _deleteKeyword(keyword);
                          },
                    deleteIcon: const Icon(Icons.close, size: 18),
                    deleteButtonTooltipMessage: 'Remove ${keyword.keyword}',
                  );
                })
                .toList(growable: false),
          ),
      ],
    );
  }
}
