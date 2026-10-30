import 'dart:ui' show Color;

import 'oklch.dart';

/// Material You seed colors — mirrors `ACCENTS` in the design's src/data.ts.
enum FlvpAccent { indigo, teal, green, rose, amber }

class FlvpAccentSpec {
  const FlvpAccentSpec(this.hue, this.chromaFactor, this.label);

  /// oklch hue of the seed color.
  final double hue;

  /// Chroma factor that keeps every derived token inside sRGB.
  final double chromaFactor;

  final String label;
}

const Map<FlvpAccent, FlvpAccentSpec> flvpAccentSpecs = {
  FlvpAccent.indigo: FlvpAccentSpec(275, 1, '靛蓝'),
  FlvpAccent.teal: FlvpAccentSpec(200, 0.72, '青碧'),
  FlvpAccent.green: FlvpAccentSpec(150, 0.72, '松绿'),
  FlvpAccent.rose: FlvpAccentSpec(12, 0.9, '玫瑰'),
  FlvpAccent.amber: FlvpAccentSpec(80, 0.65, '琥珀'),
};

/// The three stops of the Android-style palette swatch
/// (`conic-gradient(from 270deg, a 0 50%, c 50% 75%, b 75% 100%)`).
class FlvpAccentSwatch {
  const FlvpAccentSwatch(this.primary, this.accent, this.secondary);

  /// `a` — primary at 56% lightness.
  final Color primary;

  /// `c` — tertiary, hue rotated by +60.
  final Color accent;

  /// `b` — light tint.
  final Color secondary;
}

FlvpAccentSwatch flvpAccentSwatch(FlvpAccent key) {
  final spec = flvpAccentSpecs[key]!;
  return FlvpAccentSwatch(
    oklch(0.56, 0.17 * spec.chromaFactor, spec.hue),
    oklch(0.72, 0.10 * spec.chromaFactor, spec.hue + 60),
    oklch(0.86, 0.06 * spec.chromaFactor, spec.hue),
  );
}
