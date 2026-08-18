import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_image_edit_service.dart';
import '../services/image_asset_service.dart';
import '../services/user_activity_logger.dart';

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
      if (mounted) Navigator.of(context).pop(imageId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isGenerating || _isAccepting;
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
                      ? Image.network(
                          widget.sourceImageUrl,
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
