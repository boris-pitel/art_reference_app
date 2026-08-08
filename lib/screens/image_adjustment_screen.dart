import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/image_adjustment_service.dart';
import '../widgets/home_button.dart';

class ImageAdjustmentController {
  Future<void> Function()? _apply;
  final ValueNotifier<bool> hasChanges = ValueNotifier<bool>(false);

  Future<void> apply() async {
    await _apply?.call();
  }
}

class ImageAdjustmentScreen extends StatefulWidget {
  const ImageAdjustmentScreen({
    super.key,
    required this.imageBytes,
    this.embedded = false,
    this.onDone,
    this.onProcessingChanged,
    this.controller,
  });

  final Uint8List imageBytes;
  final bool embedded;
  final FutureOr<void> Function(Uint8List)? onDone;
  final ValueChanged<bool>? onProcessingChanged;
  final ImageAdjustmentController? controller;

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

  Size? _imageSize;
  String? _loadError;
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  double _straightenAngle = 0;
  int _quarterTurns = 0;
  String _ratio = 'Free';
  bool _isDetecting = false;
  bool _isApplying = false;

  double get _totalAngle => _quarterTurns * 90 + _straightenAngle;

  void _markChanged() {
    widget.controller?.hasChanges.value = true;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._apply = _done;
    _readImageSize();
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
      if (ratio != 'Free') _applyRatio(_ratioValue(ratio));
    });
    if (ratio != 'Free') _markChanged();
  }

  double? _ratioValue(String ratio) {
    switch (ratio) {
      case 'Original':
        final size = _imageSize;
        if (size == null) return null;
        final turned = _quarterTurns.isOdd;
        return turned ? size.height / size.width : size.width / size.height;
      case '1:1':
        return 1;
      case '4:5':
        return 4 / 5;
      case '16:9':
        return 16 / 9;
      case 'Custom':
        final width = double.tryParse(_widthController.text);
        final height = double.tryParse(_heightController.text);
        if (width == null || height == null || width <= 0 || height <= 0) {
          return null;
        }
        return width / height;
    }
    return null;
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

  void _updateCrop(DragUpdateDetails details, Size area, Alignment handle) {
    final dx = details.delta.dx / area.width;
    final dy = details.delta.dy / area.height;
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
    setState(() => _crop = Rect.fromLTRB(left, top, right, bottom));
    _markChanged();
  }

  Future<void> _done() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    widget.onProcessingChanged?.call(true);
    try {
      final adjusted = await ImageAdjustmentService.apply(
        bytes: widget.imageBytes,
        angle: _totalAngle,
        crop: _crop,
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
                      child: Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        cacheWidth: 1600,
                      ),
                    ),
                  ),
                  CustomPaint(painter: _CropOverlayPainter(_crop)),
                  for (final handle in const [
                    Alignment.topCenter,
                    Alignment.bottomCenter,
                  ])
                    Positioned(
                      left: _crop.left * fitted.width,
                      top: _handleTop(handle, fitted.height),
                      width: _crop.width * fitted.width,
                      height: 88,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (details) =>
                            _updateCrop(details, fitted, handle),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  for (final handle in const [
                    Alignment.centerLeft,
                    Alignment.centerRight,
                  ])
                    Positioned(
                      left: _handleLeft(handle, fitted.width),
                      top: _crop.top * fitted.height,
                      width: 88,
                      height: _crop.height * fitted.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (details) =>
                            _updateCrop(details, fitted, handle),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  for (final handle in const [
                    Alignment.topLeft,
                    Alignment.topRight,
                    Alignment.bottomLeft,
                    Alignment.bottomRight,
                  ])
                    Positioned(
                      left: _handleLeft(handle, fitted.width),
                      top: _handleTop(handle, fitted.height),
                      width: 88,
                      height: 88,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (details) =>
                            _updateCrop(details, fitted, handle),
                        child: const SizedBox.expand(),
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

  double _handleLeft(Alignment handle, double width) =>
      ((handle.x < 0 ? _crop.left : _crop.right) * width - 44).clamp(
        0.0,
        math.max(0, width - 88),
      );
  double _handleTop(Alignment handle, double height) =>
      ((handle.y < 0 ? _crop.top : _crop.bottom) * height - 44).clamp(
        0.0,
        math.max(0, height - 88),
      );

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
              ],
            ),
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Free', label: Text('Free')),
                  ButtonSegment(value: 'Original', label: Text('Original')),
                  ButtonSegment(value: '1:1', label: Text('1:1')),
                  ButtonSegment(value: '4:5', label: Text('4:5')),
                  ButtonSegment(value: '16:9', label: Text('16:9')),
                  ButtonSegment(value: 'Custom', label: Text('Custom')),
                ],
                selected: {_ratio},
                onSelectionChanged: (value) => _selectRatio(value.first),
              ),
            ),
            if (_ratio == 'Custom') ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ratioField('Width', _widthController),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 22, 12, 0),
                    child: Text(':'),
                  ),
                  _ratioField('Height', _heightController),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback? onPressed) {
    return TextButton(
      onPressed: onPressed,
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
      width: 82,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) {
          setState(() => _applyRatio(_ratioValue('Custom')));
          _markChanged();
        },
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.crop);
  final Rect crop;

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
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop;
}
