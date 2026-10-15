import 'dart:math' as math;

List<double> rgbToLab(double r, double g, double b) {
  double linear(double c) {
    c /= 255;
    return c <= .04045
        ? c / 12.92
        : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }

  r = linear(r);
  g = linear(g);
  b = linear(b);
  double f(double t) => t > math.pow(6 / 29, 3)
      ? math.pow(t, 1 / 3).toDouble()
      : t / (3 * math.pow(6 / 29, 2)) + 4 / 29;
  final x = f((.4124564 * r + .3575761 * g + .1804375 * b) / .95047);
  final y = f(.2126729 * r + .7151522 * g + .0721750 * b);
  final z = f((.0193339 * r + .1191920 * g + .9503041 * b) / 1.08883);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

/// CIEDE2000 with standard unit weighting, matching the catalogue's D65 Lab.
double deltaE2000(List<double> a, List<double> b) {
  double sq(double x) => x * x;
  double pow7(double x) => math.pow(x, 7).toDouble();
  double rad(double d) => d * math.pi / 180;
  double hue(double y, double x) =>
      (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  final c1 = math.sqrt(sq(a[1]) + sq(a[2])),
      c2 = math.sqrt(sq(b[1]) + sq(b[2]));
  final c = (c1 + c2) / 2, p25 = pow7(25);
  final g = .5 * (1 - math.sqrt(pow7(c) / (pow7(c) + p25)));
  final ap1 = (1 + g) * a[1], ap2 = (1 + g) * b[1];
  final cp1 = math.sqrt(sq(ap1) + sq(a[2])),
      cp2 = math.sqrt(sq(ap2) + sq(b[2]));
  final h1 = cp1 == 0 ? 0.0 : hue(a[2], ap1),
      h2 = cp2 == 0 ? 0.0 : hue(b[2], ap2);
  var dh = h2 - h1;
  if (cp1 * cp2 == 0) {
    dh = 0;
  } else if (dh > 180) {
    dh -= 360;
  } else if (dh < -180) {
    dh += 360;
  }
  final dl = b[0] - a[0],
      dc = cp2 - cp1,
      dH = 2 * math.sqrt(cp1 * cp2) * math.sin(rad(dh / 2));
  final l = (a[0] + b[0]) / 2, cc = (cp1 + cp2) / 2;
  final hh = cp1 * cp2 == 0
      ? h1 + h2
      : (h1 - h2).abs() <= 180
      ? (h1 + h2) / 2
      : h1 + h2 < 360
      ? (h1 + h2 + 360) / 2
      : (h1 + h2 - 360) / 2;
  final t =
      1 -
      .17 * math.cos(rad(hh - 30)) +
      .24 * math.cos(rad(2 * hh)) +
      .32 * math.cos(rad(3 * hh + 6)) -
      .20 * math.cos(rad(4 * hh - 63));
  final sl = 1 + .015 * sq(l - 50) / math.sqrt(20 + sq(l - 50)),
      sc = 1 + .045 * cc,
      sh = 1 + .015 * cc * t;
  final rt =
      -2 *
      math.sqrt(pow7(cc) / (pow7(cc) + p25)) *
      math.sin(rad(60 * math.exp(-sq((hh - 275) / 25))));
  return math.sqrt(
    math.max(
      0,
      sq(dl / sl) + sq(dc / sc) + sq(dH / sh) + rt * (dc / sc) * (dH / sh),
    ),
  );
}
