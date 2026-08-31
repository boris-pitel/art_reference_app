import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_image_edit_service.dart';
import '../services/app_image_cache.dart';
import '../services/feedback_service.dart';
import '../services/image_asset_service.dart';
import '../services/recent_input_store.dart';
import '../services/user_activity_logger.dart';
import '../widgets/cached_image.dart';

/// What the AI editor hands back: the sketch it saved, resolved before leaving.
///
/// The URL is looked up while the editor is still on screen so that the caller
/// can act the instant it closes, rather than fetching it afterwards with an
/// intermediate screen sitting visible.
class AiEditResult {
  const AiEditResult({required this.id, required this.url});

  final String id;
  final String url;
}

class AiImageEditScreen extends StatefulWidget {
  const AiImageEditScreen({
    required this.sourceImageId,
    required this.sourceImageUrl,
    required this.parentImageId,
    super.key,
  });

  final String sourceImageId;
  final String sourceImageUrl;
  final String parentImageId;

  @override
  State<AiImageEditScreen> createState() => _AiImageEditScreenState();
}

class _AiImageEditScreenState extends State<AiImageEditScreen> {
  final TextEditingController _promptController = TextEditingController();
  late final AiImageEditService _aiService = AiImageEditService(
    Supabase.instance.client,
  );
  late final ImageAssetService _imageService = ImageAssetService(
    Supabase.instance.client,
  );

  AiImageQuality _quality = AiImageQuality.medium;
  Uint8List? _previewBytes;
  bool _isGenerating = false;
  bool _isAccepting = false;

  List<String> _recentPrompts = const [];

  /// True while the compare control is held down, showing the original in the
  /// result's place.
  bool _isComparing = false;

  String? _error;

  /// The most recent sketch saved from this screen.
  ///
  /// Accepting used to close the screen and hand this back. It no longer does,
  /// so the id is held until the user actually leaves — otherwise the screen
  /// behind would never learn that sketches had been added and would show a
  /// stale list.
  String? _lastSavedImageId;
  String? _lastSavedImageUrl;

  @override
  void initState() {
    super.initState();
    _loadRecentPrompts();
  }

  Future<void> _loadRecentPrompts() async {
    final prompts = await RecentInputStore.aiPrompts();
    if (!mounted) return;

    setState(() {
      _recentPrompts = prompts;
      if (_promptController.text.isEmpty && prompts.isNotEmpty) {
        _promptController.text = prompts.first;
        _promptController.selection = TextSelection.collapsed(
          offset: _promptController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_isGenerating || _isAccepting) return;
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe the change you want AI to make.');
      return;
    }
    setState(() {
      _isGenerating = true;
      _error = null;
      _previewBytes = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final bytes = await _aiService.editImage(
        imageId: widget.sourceImageId,
        prompt: prompt,
        quality: _quality,
      );
      final recentPrompts = await RecentInputStore.rememberAiPrompt(prompt);
      UserActivityLogger.instance.record(
        operation: 'ai_image_edit_generate',
        status: 'succeeded',
        targetType: 'image',
        targetId: widget.sourceImageId,
        parentImageId: widget.parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {'quality': _quality.name, 'output_bytes': bytes.length},
      );
      if (mounted) {
        setState(() {
          _recentPrompts = recentPrompts;
          _previewBytes = bytes;
        });
      }
    } on AiQuotaExceeded catch (limit) {
      // Recorded as its own status rather than as a failure: nothing broke,
      // and counting these as failures would make the reliability figures lie.
      UserActivityLogger.instance.record(
        operation: 'ai_image_edit_generate',
        status: 'refused',
        targetType: 'image',
        targetId: widget.sourceImageId,
        parentImageId: widget.parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {'quality': _quality.name, 'reason': limit.reason},
      );
      if (mounted) {
        setState(() => _isGenerating = false);
        await _showLimitReached(limit);
      }
    } catch (error) {
      UserActivityLogger.instance.record(
        operation: 'ai_image_edit_generate',
        status: 'failed',
        targetType: 'image',
        targetId: widget.sourceImageId,
        parentImageId: widget.parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {'quality': _quality.name},
        error: error,
      );
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// Explains that the allowance ran out, and offers the way forward.
  ///
  /// A dialog rather than the red error line the other failures use, because
  /// this is not a failure: nothing went wrong and there is something the
  /// person can actually do about it.
  Future<void> _showLimitReached(AiQuotaExceeded limit) async {
    final wantsUpgrade = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.hourglass_bottom),
        title: Text(
          limit.reason == 'service'
              ? 'AI editing is resting'
              : 'That is all the AI editing for now',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(limit.message),
            if (limit.canUpgrade) ...[
              const SizedBox(height: 16),
              Text(
                '${limit.upgradeName} includes ${limit.upgradeDaily} AI edits '
                'a day and ${limit.upgradeMonthly} a month.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                // Honest about what the button does. There is no checkout yet,
                // and a button labelled Buy that quietly sends a message would
                // be a small lie the first user would catch.
                'Ask to move up a level and we will get back to you.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          if (limit.canUpgrade)
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.upgrade),
              label: Text('Ask about ${limit.upgradeName}'),
            ),
        ],
      ),
    );

    if (wantsUpgrade != true || !mounted) return;
    await _requestUpgrade(limit);
  }

  Future<void> _requestUpgrade(AiQuotaExceeded limit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Sent through the feedback path, which already emails support and
      // carries the platform and version with it, rather than inventing a
      // second channel that nobody watches.
      await FeedbackService(Supabase.instance.client).submit(
        type: FeedbackType.other,
        comment:
            'Upgrade request: would like to move to ${limit.upgradeName} '
            '(${limit.upgradeDaily} AI edits a day). '
            'Reached the ${limit.reason} limit on the current level.',
        currentScreen: 'AI image editing',
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Thank you — we have your request and will be in touch.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send the request: $error')),
      );
    }
  }

  Future<void> _accept() async {
    final bytes = _previewBytes;
    if (bytes == null || _isGenerating || _isAccepting) return;
    setState(() {
      _isAccepting = true;
      _error = null;
    });
    try {
      final imageId = await _imageService.uploadAssociatedImage(
        bytes,
        widget.parentImageId,
      );
      // Looked up now, while this screen is still on top, so that leaving is
      // instant. Doing it after the pop left the crop editor sitting visible
      // for a whole network round trip before it closed in turn — which is
      // what made it flash past on the way out.
      String? savedUrl;
      try {
        final associated = await _imageService.listAssociatedImages(
          widget.parentImageId,
        );
        savedUrl = associated
            .where((image) => image.id == imageId)
            .firstOrNull
            ?.imageUrl;
      } catch (error) {
        // Not fatal: the image is saved either way, and the screen behind can
        // reload without this. It only costs the smooth exit.
        debugPrint('Could not resolve the saved sketch URL: $error');
      }

      if (!mounted) return;

      // The prompt deliberately survives. Everything else goes, so the screen
      // looks untouched — but wording an instruction is the effortful part,
      // and the next attempt is usually a small change to it rather than
      // something written from nothing.
      _lastSavedImageUrl = savedUrl;

      setState(() {
        // Remembered so leaving still tells the screen behind that something
        // was added, even though accepting no longer leaves by itself. Not
        // shown anywhere — it is bookkeeping, not a trace.
        _lastSavedImageId = imageId;
        _previewBytes = null;
        _error = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved to sketches. Describe another change to '
            'keep editing, or go back to see it.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isGenerating || _isAccepting;
    return PopScope(
      // Intercepted so leaving carries back whatever was saved, whichever way
      // the user leaves — the back arrow, the system gesture, or the hardware
      // button. Accepting no longer closes the screen, so this is the only
      // moment the result can be handed over.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;

        final id = _lastSavedImageId;
        final url = _lastSavedImageUrl;

        Navigator.of(context).pop(
          id == null || url == null ? null : AiEditResult(id: id, url: url),
        );
      },
      child: _buildScaffold(context, busy),
    );
  }

  Widget _buildScaffold(BuildContext context, bool busy) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit with AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPreview(context),
            // Directly under the image, where somebody waiting for a result is
            // already looking, rather than under the prompt field where it
            // could be scrolled off a phone screen entirely.
            if (_error != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Describe the change',
                hintText:
                    'Example: Remove the objects from the table and preserve the lighting.',
                border: const OutlineInputBorder(),
                suffixIcon: _recentPrompts.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Recent AI prompts',
                        icon: const Icon(Icons.history),
                        onSelected: (prompt) {
                          _promptController.text = prompt;
                          _promptController.selection = TextSelection.collapsed(
                            offset: prompt.length,
                          );
                        },
                        itemBuilder: (_) => _recentPrompts
                            .map(
                              (prompt) => PopupMenuItem(
                                value: prompt,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 320),
                                  child: Text(
                                    prompt,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ),
            // Directly under the prompt, where the hand already is. The
            // quality picker and the notices below are read once and then
            // ignored; the button is used on every attempt.
            ..._buildActions(context, busy),
            const SizedBox(height: 20),
            DropdownButtonFormField<AiImageQuality>(
              initialValue: _quality,
              decoration: const InputDecoration(
                labelText: 'AI quality',
                border: OutlineInputBorder(),
              ),
              items: AiImageQuality.values
                  .map(
                    (quality) => DropdownMenuItem(
                      value: quality,
                      child: Text('${quality.label} — ${quality.description}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: busy
                  ? null
                  : (quality) {
                      if (quality != null) setState(() => _quality = quality);
                    },
            ),
            const SizedBox(height: 8),
            Text(
              'Each generation uses AI credits, including previews you reject. '
              'Medium is recommended; High costs substantially more.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _ResolutionNotice(),
          ],
        ),
      ),
    );
  }

  /// The image pane, which always says what it is showing.
  ///
  /// It used to render the source image whenever there was no result — during
  /// the whole of a sixty-second generation, and after every failure — at the
  /// same size, in the same frame, with nothing to distinguish it from output.
  /// So a failed edit looked exactly like a finished one that had changed
  /// nothing, and the error explaining it sat below the prompt field, off the
  /// bottom of a phone screen. That is reported as "it returns something and
  /// it's the original", and it is not the model's doing.
  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final hasResult = _previewBytes != null;

    // While comparing, the original is shown in the result's place — the point
    // being to judge them in the same frame at the same size, where a small
    // change is visible and a missing one is obvious.
    final showingOriginal = !hasResult || _isComparing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (showingOriginal)
                    CachedImage(
                      url: widget.sourceImageUrl,
                      cacheKey: AppImageCache.fullKey(widget.sourceImageId),
                      fit: BoxFit.contain,
                    )
                  else
                    Image.memory(_previewBytes!, fit: BoxFit.contain),

                  // Over the image rather than under the prompt. A minute-long
                  // wait whose only indication is off the bottom of the screen
                  // may as well have none.
                  if (_isGenerating || _isAccepting)
                    ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _isGenerating
                                  ? 'Editing with AI…'
                                  : 'Saving as a sketch…',
                              style: const TextStyle(color: Colors.white),
                            ),
                            if (_isGenerating) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'This usually takes about a minute.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          showingOriginal ? 'Original' : 'AI result',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasResult) ...[
          const SizedBox(height: 8),
          // Held rather than toggled, so letting go always returns to the
          // result and the control cannot be left in a state that misleads.
          //
          // This replaces comparing the two automatically. A generated image
          // is re-rendered at another resolution and re-encoded, so it never
          // matches the original byte for byte however little changed; and a
          // perceptual comparison cannot tell "the model did nothing" from
          // "the model did something small", which is most of what people ask
          // for. The person who wrote the prompt can tell in half a second.
          GestureDetector(
            onTapDown: (_) => setState(() => _isComparing = true),
            onTapUp: (_) => setState(() => _isComparing = false),
            onTapCancel: () => setState(() => _isComparing = false),
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.compare_outlined),
              label: Text(
                _isComparing ? 'Showing the original' : 'Hold to compare',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Everything to do with acting on the prompt, kept together.
  ///
  /// Placed under the prompt field rather than at the foot of the page: the
  /// quality picker and the notices are read once, while the button is used on
  /// every attempt.
  List<Widget> _buildActions(BuildContext context, bool busy) {
    return [
      // Progress and errors used to live here. They now sit on the image
      // instead: this is below the prompt field, which on a phone is below the
      // fold, so a failure after a minute of waiting was invisible at exactly
      // the moment somebody was looking hardest for an answer.
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        children: [
          if (_previewBytes != null)
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() => _previewBytes = null),
              child: const Text('Reject'),
            ),
          FilledButton.icon(
            onPressed: busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_previewBytes == null ? 'Generate' : 'Generate again'),
          ),
          if (_previewBytes != null)
            FilledButton.icon(
              onPressed: busy ? null : _accept,
              icon: const Icon(Icons.check),
              label: const Text('Accept'),
            ),
        ],
      ),
    ];
  }
}

/// Sets expectations before credits are spent: the AI returns a newly generated
/// image at the model's own resolution, so a large photo comes back smaller.
/// Surfaced up front because the drop is otherwise only discovered afterwards,
/// in the Technical panel.
class _ResolutionNotice extends StatelessWidget {
  const _ResolutionNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI editing creates a new image rather than altering your file, '
              'so large photos come back at a lower resolution — at most '
              '3840×2160 (about 8 megapixels). Your original is kept '
              'unchanged alongside the result.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
