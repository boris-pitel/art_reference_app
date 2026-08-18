import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageAdjustmentService {
  const ImageAdjustmentService._();

  static Future<double> detectStraightenAngle(Uint8List bytes) {
    return compute(_detectStraightenAngle, bytes);
  }

  static Future<Uint8List> apply({
    required Uint8List bytes,
    required double angle,
    required Rect crop,
  }) {
    return compute(_applyAdjustment, (
      bytes: bytes,
      angle: angle,
      left: crop.left,
      top: crop.top,
      width: crop.width,
      height: crop.height,
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
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}
