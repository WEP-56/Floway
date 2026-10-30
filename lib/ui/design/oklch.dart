import 'dart:math' as math;
import 'dart:ui' show Color;

/// OKLCh -> sRGB, matching the CSS `oklch()` token values of the design asset.
///
/// Uses Ottosson's OKLab matrices with a D65 white point. Every token of the
/// design stays inside sRGB through its chroma factor, so clamping is safe.
Color oklch(double lightness, double chroma, double hueDegrees) {
  final h = hueDegrees * math.pi / 180;
  final a = chroma * math.cos(h);
  final b = chroma * math.sin(h);
  final lp = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final mp = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final sp = lightness - 0.0894841775 * a - 1.2914855480 * b;
  final l3 = lp * lp * lp;
  final m3 = mp * mp * mp;
  final s3 = sp * sp * sp;
  final r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  final g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  final b2 = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;
  return Color.fromARGB(255, _srgb(r), _srgb(g), _srgb(b2));
}

double _linearToSrgb(double v) => v <= 0.0031308
    ? 12.92 * v
    : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;

int _srgb(double v) => (_linearToSrgb(v).clamp(0.0, 1.0) * 255).round();
