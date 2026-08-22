import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/saved_aspect_ratio.dart';
import '../services/image_adjustment_service.dart';
import '../services/saved_aspect_ratio_store.dart';
import '../widgets/composition_overlay.dart';
import '../widgets/home_button.dart';

typedef ImageAdjustmentProcessor =
    Future<Uint8List> Function({
      required Uint8List bytes,
      required double angle,
      required Rect crop,
      bool monochrome,
    });

class _AspectRatioPreset {
  const _AspectRatioPreset(this.key, this.label, this.width, this.height);

  final String key;
  final String label;
  final double width;
  final double height;

  double get value => width / height;
}

const _aspectRatioPresets = <_AspectRatioPreset>[
  _AspectRatioPreset('1:1', '1:1 — Square', 1, 1),
  _AspectRatioPreset('2:3', '2:3 — Portrait', 2, 3),
  _AspectRatioPreset('3:2', '3:2 — Landscape', 3, 2),
  _AspectRatioPreset('3:4', '3:4 — Portrait', 3, 4),
  _AspectRatioPreset('4:3', '4:3 — Landscape', 4, 3),
  _AspectRatioPreset('4:5', '4:5 — Portrait', 4, 5),
  _AspectRatioPreset('5:4', '5:4 — Landscape', 5, 4),
  _AspectRatioPreset('5:7', '5:7 — Photo portrait', 5, 7),
  _AspectRatioPreset('7:5', '7:5 — Photo landscape', 7, 5),
  _AspectRatioPreset('11:14', '11:14 — Photo portrait', 11, 14),
  _AspectRatioPreset('14:11', '14:11 — Photo landscape', 14, 11),
  _AspectRatioPreset('9:16', '9:16 — Screen portrait', 9, 16),
  _AspectRatioPreset('16:9', '16:9 — Screen landscape', 16, 9),
  _AspectRatioPreset('a0-p', 'A0 — Portrait', 841, 1189),
  _AspectRatioPreset('a0-l', 'A0 — Landscape', 1189, 841),
  _AspectRatioPreset('a1-p', 'A1 — Portrait', 594, 841),
  _AspectRatioPreset('a1-l', 'A1 — Landscape', 841, 594),
  _AspectRatioPreset('a2-p', 'A2 — Portrait', 420, 594),
  _AspectRatioPreset('a2-l', 'A2 — Landscape', 594, 420),
  _AspectRatioPreset('a3-p', 'A3 — Portrait', 297, 420),
  _AspectRatioPreset('a3-l', 'A3 — Landscape', 420, 297),
  _AspectRatioPreset('a4-p', 'A4 — Portrait', 210, 297),
  _AspectRatioPreset('a4-l', 'A4 — Landscape', 297, 210),
  _AspectRatioPreset('a5-p', 'A5 — Portrait', 148, 210),
  _AspectRatioPreset('a5-l', 'A5 — Landscape', 210, 148),
  _AspectRatioPreset('a6-p', 'A6 — Portrait', 105, 148),
  _AspectRatioPreset('a6-l', 'A6 — Landscape', 148, 105),
  _AspectRatioPreset('b5-p', 'B5 — Portrait', 176, 250),
  _AspectRatioPreset('b5-l', 'B5 — Landscape', 250, 176),
  _AspectRatioPreset('letter-p', 'US Letter — Portrait', 8.5, 11),
  _AspectRatioPreset('letter-l', 'US Letter — Landscape', 11, 8.5),
  _AspectRatioPreset('legal-p', 'US Legal — Portrait', 8.5, 14),
  _AspectRatioPreset('legal-l', 'US Legal — Landscape', 14, 8.5),
  _AspectRatioPreset('tabloid-p', 'Tabloid — Portrait', 11, 17),
  _AspectRatioPreset('tabloid-l', 'Tabloid — Landscape', 17, 11),
  _AspectRatioPreset('executive-p', 'US Executive — Portrait', 7.25, 10.5),
  _AspectRatioPreset('executive-l', 'US Executive — Landscape', 10.5, 7.25),
];

class ImageAdjustmentController {
  Future<void> Function()? _apply;
  final ValueNotifier<bool> hasChanges = ValueNotifier<bool>(false);

  Future<void> apply() async {
    await _apply?.call();
  }
}

enum _CropDragTarget {
  move,
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class ImageAdjustmentScreen extends StatefulWidget {
  const ImageAdjustmentScreen({
    super.key,
    required this.imageBytes,
    this.embedded = false,
    this.onDone,
    this.onProcessingChanged,
    this.controller,
    this.onEditWithAi,
    this.imageProcessor,
    this.aspectRatioStore,
  });

  final Uint8List imageBytes;
  final bool embedded;
  final FutureOr<void> Function(Uint8List)? onDone;
  final ValueChanged<bool>? onProcessingChanged;
  final ImageAdjustmentController? controller;
  final VoidCallback? onEditWithAi;
  final ImageAdjustmentProcessor? imageProcessor;
  final SavedAspectRatioStore? aspectRatioStore;

  static Future<Uint8List?> open(BuildContext context, Uint8List bytes) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => ImageAdjustmentScreen(imageBytes: bytes),
      ),
    );
  }

  @override
  State<ImageAdjustmentScreen> createState() => _ImageAdjustmentScreenState();
}

class _ImageAdjustmentScreenState extends State<ImageAdjustmentScreen> {
  final TextEditingController _widthController = TextEditingController(
    text: '3',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '2',
  );
  late final SavedAspectRatioStore _aspectRatioStore =
      widget.aspectRatioStore ?? const SavedAspectRatioStore();

  Size? _imageSize;
  String? _loadError;
  Rect _crop = const Rect.fromLTWH(0.06, 0.06, 0.88, 0.88);
  bool _cropHasBeenAdjusted = false;
  double _straightenAngle = 0;
  int _quarterTurns = 0;
  // Thirds by default, which is what this screen has always drawn.
  CompositionGrid _grid = CompositionGrid.thirds;
  bool _monochrome = false;
  String _ratio = 'Free';
  List<SavedAspectRatio> _savedRatios = const [];
  bool _isSavingRatio = false;
  bool _isDetecting = false;
  bool _isApplying = false;
  int? _activeCropPointer;
  _CropDragTarget? _activeCropTarget;
  _CropDragTarget? _hoverCropTarget;

  double get _totalAngle => _quarterTurns * 90 + _straightenAngle;

  void _markChanged() {
    widget.controller?.hasChanges.value = true;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._apply = _done;
    _readImageSize();
    _loadSavedRatios();
  }

  Future<void> _loadSavedRatios() async {
    try {
      final ratios = await _aspectRatioStore.load();
      if (mounted) setState(() => _savedRatios = ratios);
    } catch (error) {
      debugPrint('Unable to load saved aspect ratios: $error');
    }
  }

  @override
  void dispose() {
    if (widget.controller?._apply == _done) {
      widget.controller?._apply = null;
    }
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _readImageSize() async {
    try {
      final codec = await ui.instantiateImageCodec(
        widget.imageBytes,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (mounted) {
        setState(() {
          _imageSize = size;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = 'This sketch could not be opened.\n$error';
        });
      }
    }
  }

  Future<void> _autoStraighten() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      final angle = await ImageAdjustmentService.detectStraightenAngle(
        widget.imageBytes,
      );
      if (!mounted) return;
      setState(() => _straightenAngle = angle);
      if (angle != 0) _markChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            angle == 0
                ? 'The image already appears straight.'
                : 'Straightened by ${angle.abs().toStringAsFixed(1)}°.',
          ),
          duration: Duration(seconds: angle == 0 ? 3 : 5),
          action: angle == 0
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    if (mounted) setState(() => _straightenAngle = 0);
                  },
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to detect a straight line in this image.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _selectRatio(String ratio) {
    setState(() {
      _ratio = ratio;
      final saved = _savedRatioForKey(ratio);
      if (saved != null) {
        _widthController.text = _ratioNumber(saved.width);
        _heightController.text = _ratioNumber(saved.height);
      }
      if (ratio != 'Free') {
        _cropHasBeenAdjusted = true;
        _applyRatio(_ratioValue(ratio));
      }
    });
    if (ratio != 'Free') _markChanged();
  }

  double? _ratioValue(String ratio) {
    if (ratio == 'Original') {
      final size = _imageSize;
      if (size == null) return null;
      final turned = _quarterTurns.isOdd;
      return turned ? size.height / size.width : size.width / size.height;
    }
    if (ratio == 'Custom') return _customRatio()?.value;
    final saved = _savedRatioForKey(ratio);
    if (saved != null) return saved.value;
    for (final preset in _aspectRatioPresets) {
      if (preset.key == ratio) return preset.value;
    }
    return null;
  }

  SavedAspectRatio? _customRatio() {
    final width = double.tryParse(_widthController.text);
    final height = double.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return SavedAspectRatio(width: width, height: height);
  }

  SavedAspectRatio? _savedRatioForKey(String key) {
    if (!key.startsWith('saved:')) return null;
    final savedKey = key.substring('saved:'.length);
    for (final ratio in _savedRatios) {
      if (ratio.key == savedKey) return ratio;
    }
    return null;
  }

  String _savedRatioKey(SavedAspectRatio ratio) => 'saved:${ratio.key}';

  String _ratioNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  Future<void> _saveCustomRatio() async {
    if (_isSavingRatio) return;
    final ratio = _customRatio();
    if (ratio == null) {
      _showRatioMessage('Enter a width and height greater than zero.');
      return;
    }
    setState(() => _isSavingRatio = true);
    try {
      final result = await _aspectRatioStore.add(ratio);
      if (!mounted) return;
      if (result.status == SaveAspectRatioStatus.limitReached) {
        _showRatioMessage(
          'You can save up to ${SavedAspectRatioStore.maximumRatios} custom ratios. Remove one first.',
        );
        return;
      }
      await _loadSavedRatios();
      if (!mounted) return;
      _selectRatio(_savedRatioKey(result.ratio));
      _showRatioMessage(
        result.status == SaveAspectRatioStatus.duplicate
            ? 'That aspect ratio is already saved.'
            : 'Custom aspect ratio saved.',
      );
    } finally {
      if (mounted) setState(() => _isSavingRatio = false);
    }
  }

  Future<void> _removeSelectedRatio() async {
    final ratio = _savedRatioForKey(_ratio);
    if (ratio == null) return;
    await _aspectRatioStore.remove(ratio.key);
    if (!mounted) return;
    setState(() {
      _savedRatios = _savedRatios
          .where((saved) => saved.key != ratio.key)
          .toList(growable: false);
      _ratio = 'Free';
    });
    _showRatioMessage('Saved aspect ratio removed.');
  }

  void _showRatioMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _applyRatio(double? ratio) {
    if (ratio == null) return;
    final center = _crop.center;
    var width = _crop.width;
    var height = width / ratio;
    if (height > 0.9) {
      height = 0.9;
      width = height * ratio;
    }
    if (width > 0.9) {
      width = 0.9;
      height = width / ratio;
    }
    _crop = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
  }

  void _resizeCrop(Offset delta, Size area, Alignment handle) {
    final dx = delta.dx / area.width;
    final dy = delta.dy / area.height;
    var left = _crop.left;
    var top = _crop.top;
    var right = _crop.right;
    var bottom = _crop.bottom;
    if (handle.x < 0) {
      left += dx;
    } else if (handle.x > 0) {
      right += dx;
    }
    if (handle.y < 0) {
      top += dy;
    } else if (handle.y > 0) {
      bottom += dy;
    }
    const minimum = 0.08;
    left = left.clamp(0.0, right - minimum);
    right = right.clamp(left + minimum, 1.0);
    top = top.clamp(0.0, bottom - minimum);
    bottom = bottom.clamp(top + minimum, 1.0);
    final ratio = _ratioValue(_ratio);
    if (_ratio != 'Free' && ratio != null) {
      if (dy.abs() >= dx.abs()) {
        final centerX = (left + right) / 2;
        final width = ((bottom - top) * ratio).clamp(minimum, 1.0);
        left = centerX - width / 2;
        right = centerX + width / 2;
        if (left < 0) {
          right -= left;
          left = 0;
        }
        if (right > 1) {
          left -= right - 1;
          right = 1;
        }
      } else {
        final centerY = (top + bottom) / 2;
        final height = ((right - left) / ratio).clamp(minimum, 1.0);
        top = centerY - height / 2;
        bottom = centerY + height / 2;
        if (top < 0) {
          bottom -= top;
          top = 0;
        }
        if (bottom > 1) {
          top -= bottom - 1;
          bottom = 1;
        }
      }
    }
    setState(() {
      _crop = Rect.fromLTRB(left, top, right, bottom);
      _cropHasBeenAdjusted = true;
    });
    _markChanged();
  }

  void _moveCrop(Offset delta, Size area) {
    final normalizedDelta = Offset(
      delta.dx / area.width,
      delta.dy / area.height,
    );
    final maximumLeft = 1 - _crop.width;
    final maximumTop = 1 - _crop.height;
    final nextLeft = (_crop.left + normalizedDelta.dx).clamp(0.0, maximumLeft);
    final nextTop = (_crop.top + normalizedDelta.dy).clamp(0.0, maximumTop);
    final nextCrop = Rect.fromLTWH(
      nextLeft,
      nextTop,
      _crop.width,
      _crop.height,
    );
    if (nextCrop == _crop) return;
    setState(() {
      _crop = nextCrop;
      _cropHasBeenAdjusted = true;
    });
    _markChanged();
  }

  _CropDragTarget? _cropTargetAt(
    Offset position,
    Size area,
    PointerDeviceKind kind,
  ) {
    final rect = Rect.fromLTWH(
      _crop.left * area.width,
      _crop.top * area.height,
      _crop.width * area.width,
      _crop.height * area.height,
    );
    final tolerance = switch (kind) {
      PointerDeviceKind.touch || PointerDeviceKind.stylus => 40.0,
      _ => 14.0,
    };
    final nearLeft = (position.dx - rect.left).abs() <= tolerance;
    final nearRight = (position.dx - rect.right).abs() <= tolerance;
    final nearTop = (position.dy - rect.top).abs() <= tolerance;
    final nearBottom = (position.dy - rect.bottom).abs() <= tolerance;
    final withinHorizontal =
        position.dx >= rect.left - tolerance &&
        position.dx <= rect.right + tolerance;
    final withinVertical =
        position.dy >= rect.top - tolerance &&
        position.dy <= rect.bottom + tolerance;

    if (nearLeft && nearTop) return _CropDragTarget.topLeft;
    if (nearRight && nearTop) return _CropDragTarget.topRight;
    if (nearLeft && nearBottom) return _CropDragTarget.bottomLeft;
    if (nearRight && nearBottom) return _CropDragTarget.bottomRight;
    if (nearTop && withinHorizontal) return _CropDragTarget.top;
    if (nearBottom && withinHorizontal) return _CropDragTarget.bottom;
    if (nearLeft && withinVertical) return _CropDragTarget.left;
    if (nearRight && withinVertical) return _CropDragTarget.right;
    if (rect.contains(position)) return _CropDragTarget.move;
    return null;
  }

  Alignment? _alignmentForTarget(_CropDragTarget target) => switch (target) {
    _CropDragTarget.top => Alignment.topCenter,
    _CropDragTarget.bottom => Alignment.bottomCenter,
    _CropDragTarget.left => Alignment.centerLeft,
    _CropDragTarget.right => Alignment.centerRight,
    _CropDragTarget.topLeft => Alignment.topLeft,
    _CropDragTarget.topRight => Alignment.topRight,
    _CropDragTarget.bottomLeft => Alignment.bottomLeft,
    _CropDragTarget.bottomRight => Alignment.bottomRight,
    _CropDragTarget.move => null,
  };

  MouseCursor get _cropCursor =>
      switch (_activeCropTarget ?? _hoverCropTarget) {
        _CropDragTarget.move => SystemMouseCursors.move,
        _CropDragTarget.top ||
        _CropDragTarget.bottom => SystemMouseCursors.resizeUpDown,
        _CropDragTarget.left ||
        _CropDragTarget.right => SystemMouseCursors.resizeLeftRight,
        _CropDragTarget.topLeft ||
        _CropDragTarget.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        _CropDragTarget.topRight ||
        _CropDragTarget.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
        null => SystemMouseCursors.basic,
      };

  void _startCropDrag(PointerDownEvent event, Size area) {
    if (_activeCropPointer != null) return;
    final target = _cropTargetAt(event.localPosition, area, event.kind);
    if (target == null) return;
    setState(() {
      _activeCropPointer = event.pointer;
      _activeCropTarget = target;
    });
  }

  void _updateCropDrag(PointerMoveEvent event, Size area) {
    if (event.pointer != _activeCropPointer) return;
    final target = _activeCropTarget;
    if (target == null) return;
    if (target == _CropDragTarget.move) {
      _moveCrop(event.delta, area);
      return;
    }
    final alignment = _alignmentForTarget(target);
    if (alignment != null) _resizeCrop(event.delta, area, alignment);
  }

  void _endCropDrag(PointerEvent event) {
    if (event.pointer != _activeCropPointer) return;
    setState(() {
      _activeCropPointer = null;
      _activeCropTarget = null;
    });
  }

  Future<void> _done() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    widget.onProcessingChanged?.call(true);
    // Give Flutter a frame to display progress before expensive image work.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final adjusted =
          await (widget.imageProcessor ?? ImageAdjustmentService.apply)(
            bytes: widget.imageBytes,
            angle: _totalAngle,
            crop: _cropHasBeenAdjusted
                ? _crop
                : const Rect.fromLTWH(0, 0, 1, 1),
            monochrome: _monochrome,
          );
      if (!mounted) return;
      final onDone = widget.onDone;
      if (onDone != null) {
        await onDone(adjusted);
      } else {
        Navigator.of(context).pop(adjusted);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to adjust the image: $error')),
        );
      }
    } finally {
      widget.onProcessingChanged?.call(false);
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final loadError = _loadError;
    final body = SafeArea(
      child: loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  loadError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : size == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildPreview(size)),
                _buildControls(),
              ],
            ),
    );
    if (widget.embedded) {
      return ColoredBox(color: Colors.black, child: body);
    }
    return PopScope(
      canPop: !_isApplying,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leadingWidth: 80,
          leading: TextButton(
            onPressed: _isApplying ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          title: const Text('Crop & Straighten'),
          actions: [
            HomeButton(enabled: !_isApplying),
            TextButton(
              onPressed: _isApplying ? null : _done,
              child: _isApplying
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Done'),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildPreview(Size sourceSize) {
    final radians = _totalAngle * math.pi / 180;
    final rotatedWidth =
        sourceSize.width * math.cos(radians).abs() +
        sourceSize.height * math.sin(radians).abs();
    final rotatedHeight =
        sourceSize.width * math.sin(radians).abs() +
        sourceSize.height * math.cos(radians).abs();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = applyBoxFit(
            BoxFit.contain,
            Size(rotatedWidth, rotatedHeight),
            constraints.biggest,
          ).destination;
          return Center(
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: Transform.rotate(
                      angle: radians,
                      child: _monochrome
                          ? ColorFiltered(
                              colorFilter: monochromeFilter,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                cacheWidth: 1600,
                              ),
                            )
                          : Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              cacheWidth: 1600,
                            ),
                    ),
                  ),
                  CustomPaint(painter: _CropOverlayPainter(_crop, _grid)),
                  Positioned.fill(
                    child: MouseRegion(
                      cursor: _cropCursor,
                      onHover: (event) {
                        if (_activeCropPointer != null) return;
                        final target = _cropTargetAt(
                          event.localPosition,
                          fitted,
                          event.kind,
                        );
                        if (target != _hoverCropTarget) {
                          setState(() => _hoverCropTarget = target);
                        }
                      },
                      onExit: (_) {
                        if (_activeCropPointer == null &&
                            _hoverCropTarget != null) {
                          setState(() => _hoverCropTarget = null);
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _startCropDrag(event, fitted),
                        onPointerMove: (event) =>
                            _updateCropDrag(event, fitted),
                        onPointerUp: _endCropDrag,
                        onPointerCancel: _endCropDrag,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _toolButton(Icons.crop, 'Crop', null)),
                Expanded(
                  child: _toolButton(
                    Icons.rotate_90_degrees_cw,
                    'Rotate 90°',
                    () {
                      setState(() {
                        _quarterTurns = (_quarterTurns + 1) % 4;
                        if (_ratio != 'Free') _applyRatio(_ratioValue(_ratio));
                      });
                      _markChanged();
                    },
                  ),
                ),
                Expanded(
                  child: _toolButton(
                    Icons.auto_fix_high,
                    'Auto straighten',
                    _isDetecting ? null : _autoStraighten,
                  ),
                ),
                Expanded(
                  child: _toolButton(
                    Icons.contrast,
                    'Monochrome',
                    () {
                      setState(() => _monochrome = !_monochrome);
                      // Unlike the grid, this one changes the pixels that get
                      // saved, so it counts as an edit.
                      _markChanged();
                    },
                    selected: _monochrome,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.grid_on, size: 18),
                const SizedBox(width: 8),
                const Text('Guides'),
                const Spacer(),
                // A guide only: never applied to the saved image, so changing
                // it deliberately does not mark the edit as changed.
                SegmentedButton<CompositionGrid>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final option in CompositionGrid.values)
                      ButtonSegment(
                        value: option,
                        label: Text(option.label),
                      ),
                  ],
                  selected: {_grid},
                  onSelectionChanged: (selection) =>
                      setState(() => _grid = selection.first),
                ),
              ],
            ),
            if (widget.onEditWithAi != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _isApplying ? null : widget.onEditWithAi,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Edit with AI'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Straighten angle'),
                const Spacer(),
                Text(
                  '${_straightenAngle >= 0 ? '+' : ''}${_straightenAngle.toStringAsFixed(1)}°',
                ),
              ],
            ),
            Slider(
              value: _straightenAngle,
              min: -10,
              max: 10,
              divisions: 200,
              onChanged: (value) {
                setState(() => _straightenAngle = value);
                _markChanged();
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _ratio,
                    isExpanded: true,
                    menuMaxHeight: 420,
                    decoration: const InputDecoration(
                      labelText: 'Aspect ratio',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'Free',
                        child: Text('Free'),
                      ),
                      const DropdownMenuItem(
                        value: 'Original',
                        child: Text('Original'),
                      ),
                      for (final preset in _aspectRatioPresets)
                        DropdownMenuItem(
                          value: preset.key,
                          child: Text(
                            preset.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      for (final ratio in _savedRatios)
                        DropdownMenuItem(
                          value: _savedRatioKey(ratio),
                          child: Text(
                            ratio.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(
                        value: 'Custom',
                        child: Text('Custom…'),
                      ),
                    ],
                    onChanged: _isApplying
                        ? null
                        : (value) {
                            if (value != null) _selectRatio(value);
                          },
                  ),
                ),
                if (_ratio == 'Custom')
                  SizedBox(
                    width: 220,
                    child: Row(
                      children: [
                        _ratioField('Width', _widthController),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: Text(':'),
                        ),
                        _ratioField('Height', _heightController),
                        IconButton(
                          onPressed: _isSavingRatio ? null : _saveCustomRatio,
                          icon: _isSavingRatio
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bookmark_add_outlined),
                          tooltip:
                              'Save custom ratio (${_savedRatios.length}/${SavedAspectRatioStore.maximumRatios})',
                        ),
                      ],
                    ),
                  ),
                if (_savedRatioForKey(_ratio) != null)
                  IconButton(
                    onPressed: _removeSelectedRatio,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove saved ratio',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: selected
          ? TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              backgroundColor: theme.colorScheme.secondaryContainer,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _ratioField(String label, TextEditingController controller) {
    return SizedBox(
      width: 68,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) {
          setState(() {
            _cropHasBeenAdjusted = true;
            _applyRatio(_ratioValue('Custom'));
          });
          _markChanged();
        },
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.crop, this.grid);
  final Rect crop;
  final CompositionGrid grid;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addRect(rect)
        ..fillType = PathFillType.evenOdd,
      shade,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, 15, handleFill);
      canvas.drawCircle(point, 15, handleStroke);
    }
    // Inside the crop, not over the whole image: the crop is the picture the
    // artist is going to end up with, so a third has to be a third of that.
    CompositionGridPainter(grid: grid, area: rect).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.grid != grid;
}
