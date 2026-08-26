import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_image_edit_service.dart';
import '../services/app_image_cache.dart';
import '../services/feedback_service.dart';
import '../services/image_asset_service.dart';
import '../services/user_activity_logger.dart';
import '../widgets/cached_image.dart';

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
  String? _error;

  /// The most recent sketch saved from this screen.
  ///
  /// Accepting used to close the screen and hand this back. It no longer does,
  /// so the id is held until the user actually leaves — otherwise the screen
  /// behind would never learn that sketches had been added and would show a
  /// stale list.
  String? _lastSavedImageId;

  /// How many sketches this visit has saved, so the screen can say so.
  ///
  /// The preview is cleared on accept, so without this the image simply
  /// disappears and the only confirmation is a snackbar that fades.
  int _savedCount = 0;

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
      UserActivityLogger.instance.record(
        operation: 'ai_image_edit_generate',
        status: 'succeeded',
        targetType: 'image',
        targetId: widget.sourceImageId,
        parentImageId: widget.parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: {'quality': _quality.name, 'output_bytes': bytes.length},
      );
      if (mounted) setState(() => _previewBytes = bytes);
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
      if (!mounted) return;

      setState(() {
        // Remembered so leaving still tells the screen behind that something
        // was added, even though accepting no longer leaves by itself.
        _lastSavedImageId = imageId;
        _savedCount += 1;
        // Cleared so the same result cannot be saved twice. Without this,
        // tapping Accept again would file a second identical sketch.
        _previewBytes = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to sketches. Describe another change to '
              'keep editing, or go back to see it.'),
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
        Navigator.of(context).pop(_lastSavedImageId);
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
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _previewBytes == null
                      ? CachedImage(
                          url: widget.sourceImageUrl,
                          cacheKey: AppImageCache.fullKey(widget.sourceImageId),
                          fit: BoxFit.contain,
                        )
                      : Image.memory(_previewBytes!, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Describe the change',
                hintText:
                    'Example: Remove the objects from the table and preserve the lighting.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (_isGenerating || _isAccepting) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _isGenerating
                    ? 'AI is editing the image…'
                    : 'Saving as an associated image…',
              ),
            ],
            if (_savedCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _savedCount == 1
                          ? 'One AI image saved to this reference’s sketches.'
                          : '$_savedCount AI images saved to this '
                                'reference’s sketches.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
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
                  label: Text(
                    _previewBytes == null ? 'Generate' : 'Generate again',
                  ),
                ),
                if (_previewBytes != null)
                  FilledButton.icon(
                    onPressed: busy ? null : _accept,
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
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
