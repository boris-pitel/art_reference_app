import 'package:flutter/material.dart';

/// How many pieces the picture is cut into.
///
/// Named for the cells an artist sees rather than the lines drawn: thirds is
/// the familiar rule-of-thirds grid, which is two lines each way, not three.
enum CompositionGrid {
  none(0, 'Off'),
  halves(2, '2 × 2'),
  thirds(3, '3 × 3'),
  quarters(4, '4 × 4');

  const CompositionGrid(this.divisions, this.label);

  /// Cells along each edge. One less than this is the number of lines drawn.
  final int divisions;
  final String label;
}

/// Draws division lines over a picture.
///
/// The lines are a guide and never touch the image itself: nothing here is
/// baked into what gets saved. [area] is where the picture actually sits, which
/// is not the whole canvas — on the edit screen it is the crop rectangle, and
/// in the viewer it is the letterboxed image inside a larger black box. Drawing
/// over the full canvas instead would put the lines in the wrong places, which
/// is worse than not drawing them.
class CompositionGridPainter extends CustomPainter {
  const CompositionGridPainter({
    required this.grid,
    this.area,
    this.color = Colors.white,
    this.opacity = 0.55,
  });

  final CompositionGrid grid;
  final Rect? area;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.divisions < 2) return;

    final rect = area ?? (Offset.zero & size);
    if (rect.width <= 0 || rect.height <= 0) return;

    // Two passes: a dark line under a light one, so the grid stays visible over
    // both a bright sky and a dark shadow. A single colour disappears into one
    // or the other on most references.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: opacity * 0.5)
      ..strokeWidth = 2
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..isAntiAlias = true;

    for (var i = 1; i < grid.divisions; i++) {
      final x = rect.left + rect.width * i / grid.divisions;
      final y = rect.top + rect.height * i / grid.divisions;

      for (final paint in [shadow, line]) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(CompositionGridPainter oldDelegate) =>
      oldDelegate.grid != grid ||
      oldDelegate.area != area ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

/// The rectangle a [BoxFit.contain] image actually occupies inside [box].
///
/// An overlay has to know this: the widget fills the whole viewport but the
/// picture inside it is letterboxed, and a grid drawn on the viewport would
/// divide the black bars along with the image.
Rect containedImageRect(Size box, Size image) {
  if (image.width <= 0 || image.height <= 0) return Offset.zero & box;

  final scale = (box.width / image.width) < (box.height / image.height)
      ? box.width / image.width
      : box.height / image.height;
  final width = image.width * scale;
  final height = image.height * scale;

  return Rect.fromLTWH(
    (box.width - width) / 2,
    (box.height - height) / 2,
    width,
    height,
  );
}
