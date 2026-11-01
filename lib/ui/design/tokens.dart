import 'dart:ui' show Color, Offset;

import 'package:flutter/painting.dart' show BoxShadow;

import 'accents.dart';
import 'oklch.dart';

/// The full MD3 tonal token set derived from one seed hue, mirroring the
/// `:root` and `[data-theme="dark"]` blocks of the design's src/index.css.
class FlvpColors {
  const FlvpColors({
    required this.canvas,
    required this.frame,
    required this.surface,
    required this.surf2,
    required this.surf3,
    required this.dialog,
    required this.tile,
    required this.primary,
    required this.onprimary,
    required this.pcontainer,
    required this.onpcontainer,
    required this.scontainer,
    required this.onscontainer,
    required this.invprimary,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hair,
    required this.ok,
    required this.warn,
    required this.err,
    required this.dark,
  });

  final Color canvas;
  final Color frame;
  final Color surface;
  final Color surf2;
  final Color surf3;
  final Color dialog;
  final Color tile;
  final Color primary;
  final Color onprimary;
  final Color pcontainer;
  final Color onpcontainer;
  final Color scontainer;
  final Color onscontainer;
  final Color invprimary;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color hair;
  final Color ok;
  final Color warn;
  final Color err;
  final bool dark;

  /// `hover:bg-ink/[0.045]`, `bg-ink/[0.06]` … — shared MD3 state layers.
  Color inkHover([double alpha = 0.045]) => ink.withValues(alpha: alpha);

  /// `hover:bg-ink/[0.07]` and friends — the stronger state layer.
  Color inkLayer([double alpha = 0.07]) => ink.withValues(alpha: alpha);
}

FlvpColors flvpLightColors(FlvpAccent accent) {
  final spec = flvpAccentSpecs[accent]!;
  return flvpLightColorsOfHue(spec.hue, chromaFactor: spec.chromaFactor);
}

/// 主题色由上游 ThemeProps 决定后，界面按它的色相重新生成整套 token。
FlvpColors flvpLightColorsOfHue(double hue, {double chromaFactor = 1}) {
  final h = hue;
  final k = chromaFactor;
  return FlvpColors(
    canvas: oklch(0.982, 0.006, h),
    frame: oklch(0.944, 0.014, h),
    surface: oklch(1, 0, h),
    surf2: oklch(0.952, 0.012, h),
    surf3: oklch(0.91, 0.018, h),
    dialog: oklch(0.966, 0.012, h),
    tile: oklch(1, 0, h),
    primary: oklch(0.5, 0.17 * k, h),
    onprimary: oklch(1, 0, h),
    pcontainer: oklch(0.915, 0.05 * k, h),
    onpcontainer: oklch(0.32, 0.12 * k, h),
    scontainer: oklch(0.912, 0.03, h),
    onscontainer: oklch(0.28, 0.045, h),
    invprimary: oklch(0.82, 0.1 * k, h),
    ink: oklch(0.22, 0.014, h),
    ink2: oklch(0.45, 0.02, h),
    ink3: oklch(0.62, 0.018, h),
    hair: oklch(0.88, 0.015, h),
    ok: const Color(0xff0b8a5a),
    warn: const Color(0xffb06a00),
    err: const Color(0xffc62f2a),
    dark: false,
  );
}

FlvpColors flvpDarkColors(FlvpAccent accent) {
  final spec = flvpAccentSpecs[accent]!;
  return flvpDarkColorsOfHue(spec.hue, chromaFactor: spec.chromaFactor);
}

/// [pureBlack] 对应上游 ThemeProps.pureBlack：深色下把底色压到纯黑。
FlvpColors flvpDarkColorsOfHue(
  double hue, {
  double chromaFactor = 1,
  bool pureBlack = false,
}) {
  final h = hue;
  final k = chromaFactor;
  return FlvpColors(
    canvas: pureBlack ? const Color(0xff000000) : oklch(0.165, 0.01, h),
    frame: pureBlack ? const Color(0xff070707) : oklch(0.205, 0.013, h),
    surface: pureBlack ? const Color(0xff0d0d0d) : oklch(0.228, 0.014, h),
    surf2: pureBlack ? const Color(0xff151515) : oklch(0.272, 0.016, h),
    surf3: pureBlack ? const Color(0xff1d1d1d) : oklch(0.322, 0.018, h),
    dialog: pureBlack ? const Color(0xff121212) : oklch(0.245, 0.016, h),
    tile: pureBlack ? const Color(0xff1a1a1a) : oklch(0.295, 0.017, h),
    primary: oklch(0.8, 0.11 * k, h),
    onprimary: oklch(0.27, 0.12 * k, h),
    pcontainer: oklch(0.36, 0.11 * k, h),
    onpcontainer: oklch(0.92, 0.04 * k, h),
    scontainer: oklch(0.34, 0.035, h),
    onscontainer: oklch(0.9, 0.025, h),
    invprimary: oklch(0.5, 0.17 * k, h),
    ink: oklch(0.93, 0.008, h),
    ink2: oklch(0.77, 0.015, h),
    ink3: oklch(0.58, 0.016, h),
    hair: oklch(0.33, 0.015, h),
    ok: const Color(0xff5fd69b),
    warn: const Color(0xfff2c46b),
    err: const Color(0xffff9a92),
    dark: true,
  );
}

/// Elevation tokens from the design's `@theme` block.
abstract final class FlvpElevation {
  /// `--shadow-card`
  static const card = [
    BoxShadow(color: Color(0x0d181430), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x29181430),
      offset: Offset(0, 8),
      blurRadius: 22,
      spreadRadius: -12,
    ),
  ];

  /// `--shadow-float`
  static const float = [
    BoxShadow(color: Color(0x1a121024), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(
      color: Color(0x52121024),
      offset: Offset(0, 18),
      blurRadius: 42,
      spreadRadius: -12,
    ),
  ];

  /// `--shadow-win`
  static const window = [
    BoxShadow(color: Color(0x0f121024), offset: Offset(0, 2), blurRadius: 8),
    BoxShadow(
      color: Color(0x6b121024),
      offset: Offset(0, 50),
      blurRadius: 100,
      spreadRadius: -30,
    ),
  ];

  /// `--shadow-phone`
  static const phone = [
    BoxShadow(color: Color(0x33101018), offset: Offset(0, 4), blurRadius: 10),
    BoxShadow(
      color: Color(0x80101018),
      offset: Offset(0, 44),
      blurRadius: 90,
      spreadRadius: -22,
    ),
  ];
}
