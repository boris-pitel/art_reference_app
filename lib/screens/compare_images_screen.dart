import 'package:flutter/material.dart';

import '../services/app_image_cache.dart';
import '../widgets/cached_image.dart';
import '../widgets/home_button.dart';

/// How the two images are shown against each other.
enum CompareMode {
  /// Stacked, with a slider dissolving one into the other.
  blend('Blend'),

  /// Two panes, zoomed together.
  sideBySide('Side by side'),

  /// One at a time, swapped by holding a button.
  flip('Flip');

  const CompareMode(this.label);
  final String label;
}

/// Two images, compared.
///
/// It answers two different questions, which is why there are modes rather
/// than one presentation. "Is my drawing accurate?" is answered by laying the
/// sketch over the reference and dissolving between them — at half opacity the
/// eye catches a jaw set too low or a shoulder too wide, which is invisible
/// when the pictures are looked at one after the other. "Which of these is
/// better?" is answered by seeing both at once.
///
/// Neither mechanic is new. Artists have held a drawing against a reference on
/// tracing paper for centuries, and astronomers found Pluto by alternating two
/// photographs of the same sky because the eye notices movement far better
/// than it notices difference. What is unusual is having it here, in the
/// library that already knows which reference a sketch belongs to — so
/// comparing the two is one tap with nothing to choose.
class CompareImagesScreen extends StatefulWidget {
  const CompareImagesScreen({
    required this.leftImageId,
    required this.leftImageUrl,
    required this.leftLabel,
    required this.rightImageId,
    required this.rightImageUrl,
    required this.rightLabel,
    super.key,
  });

  /// The image underneath in blend mode, and on the left side by side.
  /// Usually the reference.
  final String leftImageId;
  final String leftImageUrl;
  final String leftLabel;

  /// The image on top, and the one that moves when aligning.
  /// Usually the sketch.
  final String rightImageId;
  final String rightImageUrl;
  final String rightLabel;

  @override
  State<CompareImagesScreen> createState() => _CompareImagesScreenState();
}

class _CompareImagesScreenState extends State<CompareImagesScreen> {
  CompareMode _mode = CompareMode.blend;

  /// How much of the top image is shown, 0 to 1.
  double _blend = 0.5;

  /// True while the flip control is held.
  bool _showingRight = false;

  /// Drives both panes in side-by-side, so the two are always compared at the
  /// same magnification. Comparing two hands at different sizes says nothing.
  final TransformationController _sharedZoom = TransformationController();

  /// Aligns the top image in blend mode.
  ///
  /// A sketch and its reference are almost never framed identically — a
  /// different distance, a slight angle, a tighter crop. Without this the
  /// overlay is two pictures that happen to be stacked, and the comparison
  /// that makes the whole screen worth having cannot be made.
  final TransformationController _alignment = TransformationController();

  @override
  void dispose() {
    _sharedZoom.dispose();
    _alignment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          if (_mode == CompareMode.blend)
            IconButton(
              onPressed: _alignment.value.isIdentity()
                  ? null
                  : () => setState(() {
                      _alignment.value = Matrix4.identity();
                    }),
              icon: const Icon(Icons.center_focus_strong_outlined),
              tooltip: 'Reset the alignment',
            ),
          const HomeButton(),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildStage()),
          _buildControls(context),
        ],
      ),
    );
  }

  Widget _buildStage() {
    switch (_mode) {
      case CompareMode.blend:
        return _buildBlend();
      case CompareMode.sideBySide:
        return _buildSideBySide();
      case CompareMode.flip:
        return _buildFlip();
    }
  }

  Widget _buildBlend() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _image(widget.leftImageId, widget.leftImageUrl),
        // Only the top image moves. Moving both would be the same as moving
        // neither, and the point is to bring one onto the other.
        InteractiveViewer(
          transformationController: _alignment,
          minScale: 0.4,
          maxScale: 5,
          child: Opacity(
            opacity: _blend,
            child: _image(widget.rightImageId, widget.rightImageUrl),
          ),
        ),
        _label(widget.leftLabel, alignment: Alignment.topLeft),
        _label(widget.rightLabel, alignment: Alignment.topRight),
      ],
    );
  }

  Widget _buildSideBySide() {
    return Row(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _sharedZoom,
                minScale: 0.5,
                maxScale: 5,
                child: _image(widget.leftImageId, widget.leftImageUrl),
              ),
              _label(widget.leftLabel, alignment: Alignment.topLeft),
            ],
          ),
        ),
        const VerticalDivider(width: 2, color: Colors.white24),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _sharedZoom,
                minScale: 0.5,
                maxScale: 5,
                child: _image(widget.rightImageId, widget.rightImageUrl),
              ),
              _label(widget.rightLabel, alignment: Alignment.topLeft),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlip() {
    final id = _showingRight ? widget.rightImageId : widget.leftImageId;
    final url = _showingRight ? widget.rightImageUrl : widget.leftImageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        _image(id, url),
        _label(
          _showingRight ? widget.rightLabel : widget.leftLabel,
          alignment: Alignment.topLeft,
        ),
      ],
    );
  }

  Widget _image(String id, String url) {
    return CachedImage(
      url: url,
      cacheKey: AppImageCache.fullKey(id),
      fit: BoxFit.contain,
      placeholder: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorWidget: (context, error) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: Colors.white),
            SizedBox(height: 12),
            Text(
              'Unable to load this image.',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mode == CompareMode.blend) _buildBlendSlider(context),
              if (_mode == CompareMode.flip) _buildFlipButton(context),
              if (_mode == CompareMode.sideBySide)
                Text(
                  'Both sides zoom together.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              SegmentedButton<CompareMode>(
                segments: [
                  for (final mode in CompareMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlendSlider(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            widget.leftLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          flex: 4,
          child: Slider(
            value: _blend,
            onChanged: (value) => setState(() => _blend = value),
          ),
        ),
        Flexible(
          child: Text(
            widget.rightLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildFlipButton(BuildContext context) {
    // Held rather than toggled: letting go always returns to the same image,
    // so the control cannot be left in a state that misleads about which
    // picture is on screen.
    return GestureDetector(
      onTapDown: (_) => setState(() => _showingRight = true),
      onTapUp: (_) => setState(() => _showingRight = false),
      onTapCancel: () => setState(() => _showingRight = false),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.compare_outlined),
        label: Text(
          _showingRight
              ? 'Showing ${widget.rightLabel}'
              : 'Hold to see ${widget.rightLabel}',
        ),
      ),
    );
  }
}
