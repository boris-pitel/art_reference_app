/// Proportions an artist is likely to be matching, in landscape orientation.
///
/// Photographs rarely divide into tidy whole numbers — a 4032 × 3024 phone shot
/// reduces to 4 : 3, but a cropped one can reduce to something like 2711 : 1807,
/// which is accurate and useless. Naming the nearest familiar proportion is what
/// answers the question actually being asked, which is what canvas this fits.
const List<(int, int)> _familiarRatios = [
  (1, 1),
  (6, 5),
  (5, 4),
  (4, 3),
  (7, 5),
  (3, 2),
  (16, 10),
  (5, 3),
  (16, 9),
  (2, 1),
  (21, 9),
];

/// How far from a familiar proportion still counts as that proportion.
///
/// Half a percent: tight enough that 3 : 2 and 7 : 5 stay distinct — they are
/// only 1.7% apart — and loose enough to absorb the rounding of a hand-dragged
/// crop.
const double _snapTolerance = 0.005;

int _greatestCommonDivisor(int a, int b) {
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

/// A readable aspect ratio, such as `3 : 2 (1.50)`.
///
/// The decimal is always shown because it is what compares two ratios at a
/// glance; the whole numbers are what map onto a canvas.
String describeAspectRatio(int width, int height) {
  if (width <= 0 || height <= 0) return 'unknown';

  final ratio = width / height;
  final decimal = ratio >= 1
      ? '${ratio.toStringAsFixed(2)} : 1'
      : '1 : ${(1 / ratio).toStringAsFixed(2)}';

  final divisor = _greatestCommonDivisor(width, height);
  final reducedWidth = width ~/ divisor;
  final reducedHeight = height ~/ divisor;

  // An exact reduction is only worth showing when it is small enough to mean
  // something. 4 : 3 is information; 2711 : 1807 is noise.
  if (reducedWidth <= 40 && reducedHeight <= 40) {
    return '$reducedWidth : $reducedHeight  ($decimal)';
  }

  for (final (long, short) in _familiarRatios) {
    for (final (candidateWidth, candidateHeight) in [
      (long, short),
      (short, long),
    ]) {
      final candidate = candidateWidth / candidateHeight;
      if ((ratio - candidate).abs() / candidate <= _snapTolerance) {
        return '≈ $candidateWidth : $candidateHeight  ($decimal)';
      }
    }
  }

  return decimal;
}
