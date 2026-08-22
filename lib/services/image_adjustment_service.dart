import 'dart:math' as math;
import 'dart:ui' show ColorFilter, Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Rec. 709 luminance weights.
///
/// Deliberately not an average of the three channels. Averaging renders a
/// saturated red and a mid green as the same grey, which is exactly the mistake
/// an artist switches to monochrome to catch — a values check that lies is
/// worse than no values check. These weights are what the eye actually does.
const double luminanceRed = 0.2126;
const double luminanceGreen = 0.7152;
const double luminanceBlue = 0.0722;

/// The on-screen preview of [ImageAdjustmentService.apply] with monochrome on.
///
/// Shares its weights with the baked conversion below, because a preview drawn
/// with different constants would quietly disagree with the file that gets
/// saved.
const ColorFilter monochromeFilter = ColorFilter.matrix(<double>[
  luminanceRed, luminanceGreen, luminanceBlue, 0, 0, //
  luminanceRed, luminanceGreen, luminanceBlue, 0, 0, //
  luminanceRed, luminanceGreen, luminanceBlue, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class ImageAdjustmentService {
  const ImageAdjustmentService._();

  static Future<double> detectStraightenAngle(Uint8List bytes) {
    return compute(_detectStraightenAngle, bytes);
  }

  /// [gridDivisions] draws division lines into the image itself — the grid
  /// method for transferring a drawing, where the point is to keep the lines.
  /// Zero or one leaves the picture unmarked.
  static Future<Uint8List> apply({
    required Uint8List bytes,
    required double angle,
    required Rect crop,
    bool monochrome = false,
    int gridDivisions = 0,
  }) {
    return compute(_applyAdjustment, (
      bytes: bytes,
      angle: angle,
      left: crop.left,
      top: crop.top,
      width: crop.width,
      height: crop.height,
      monochrome: monochrome,
      gridDivisions: gridDivisions,
    ));
  }
}

double _detectStraightenAngle(Uint8List bytes) {
  var source = img.decodeImage(bytes);
  if (source == null) {
    throw const FormatException('The selected file is not a supported image.');
  }
  source = img.bakeOrientation(source);
  if (source.width > 420) {
    source = img.copyResize(source, width: 420);
  }

  final width = source.width;
  final height = source.height;
  if (width < 16 || height < 16) return 0;

  final edges = <({int x, int y, double weight})>[];
  for (var y = 2; y < height - 2; y += 2) {
    for (var x = 2; x < width - 2; x += 2) {
      final above = source.getPixel(x, y - 2).luminanceNormalized;
      final below = source.getPixel(x, y + 2).luminanceNormalized;
      final weight = (below - above).abs().toDouble();
      if (weight > 0.16) edges.add((x: x, y: y, weight: weight));
    }
  }
  if (edges.length < 40) return 0;

  var bestAngle = 0.0;
  var bestScore = -1.0;
  final bins = List<double>.filled(height + 80, 0);
  for (var candidate = -10.0; candidate <= 10.001; candidate += 0.25) {
    bins.fillRange(0, bins.length, 0);
    final slope = math.tan(candidate * math.pi / 180);
    for (final edge in edges) {
      final projected = (edge.y - slope * (edge.x - width / 2) + 40).round();
      if (projected >= 0 && projected < bins.length) {
        bins[projected] += edge.weight;
      }
    }
    var score = 0.0;
    for (final value in bins) {
      score += value * value;
    }
    if (score > bestScore) {
      bestScore = score;
      bestAngle = candidate;
    }
  }
  final correction = -bestAngle;
  return correction.abs() < 0.35 ? 0 : correction.clamp(-10.0, 10.0);
}

Uint8List _applyAdjustment(
  ({
    Uint8List bytes,
    double angle,
    double left,
    double top,
    double width,
    double height,
    bool monochrome,
    int gridDivisions,
  })
  data,
) {
  var source = img.decodeImage(data.bytes);
  if (source == null) {
    throw const FormatException('The selected file is not a supported image.');
  }
  source = img.bakeOrientation(source);
  if (data.angle.abs() > 0.01) {
    source = img.copyRotate(
      source,
      angle: data.angle,
      interpolation: img.Interpolation.linear,
    );
  }

  final x = math.min(
    (data.left.clamp(0.0, 1.0) * source.width).round(),
    source.width - 1,
  );
  final y = math.min(
    (data.top.clamp(0.0, 1.0) * source.height).round(),
    source.height - 1,
  );
  final cropWidth = (data.width.clamp(0.01, 1.0) * source.width).round().clamp(
    1,
    source.width - x,
  );
  final cropHeight = (data.height.clamp(0.01, 1.0) * source.height)
      .round()
      .clamp(1, source.height - y);
  final cropped = img.copyCrop(
    source,
    x: x,
    y: y,
    width: cropWidth,
    height: cropHeight,
  );

  // Written out rather than delegating to img.grayscale, whose weights are its
  // own business and could drift from the preview filter. The preview and the
  // saved file have to agree, so both read the same three constants.
  if (data.monochrome) {
    for (final pixel in cropped) {
      final value =
          pixel.r * luminanceRed +
          pixel.g * luminanceGreen +
          pixel.b * luminanceBlue;
      pixel.setRgb(value, value, value);
    }
  }

  _drawGrid(cropped, data.gridDivisions);

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}

/// Draws the division lines into the picture.
///
/// Applied after the crop, so the lines divide what the artist actually keeps,
/// and after any monochrome pass, so the grid is the colour it was meant to be
/// rather than a desaturated version of it.
void _drawGrid(img.Image image, int divisions) {
  if (divisions < 2) return;

  // Scaled to the picture: a one-pixel line is invisible on a 6000px reference
  // and overwhelming on a 400px one.
  final shortest = math.min(image.width, image.height);
  final core = math.max(2, (shortest / 700).round());

  // A light line inside a dark one, so the grid survives a bright sky and a
  // dark shadow alike — a single colour disappears into one or the other. The
  // halo is exactly twice the core, leaving a dark edge half the core's width
  // on each side: enough to separate the line from a pale background without
  // the dark swallowing the light and leaving a line that vanishes in shadow.
  final passes = [
    (color: img.ColorRgb8(0, 0, 0), thickness: core * 2),
    (color: img.ColorRgb8(255, 255, 255), thickness: core),
  ];

  for (final pass in passes) {
    for (var i = 1; i < divisions; i++) {
      final x = (image.width * i / divisions).round();
      final y = (image.height * i / divisions).round();

      img.drawLine(
        image,
        x1: x,
        y1: 0,
        x2: x,
        y2: image.height - 1,
        color: pass.color,
        thickness: pass.thickness,
      );
      img.drawLine(
        image,
        x1: 0,
        y1: y,
        x2: image.width - 1,
        y2: y,
        color: pass.color,
        thickness: pass.thickness,
      );
    }
  }
}
