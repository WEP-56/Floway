import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('the palette follows the hue the theme seed provides', () {
    final warm = flvpLightColorsOfHue(30);
    final cool = flvpLightColorsOfHue(260);

    expect(warm.primary, isNot(cool.primary));
    expect(warm.dark, isFalse);
    expect(cool.dark, isFalse);
    // Text stays at the same lightness; only a trace of the hue reaches it.
    expect(
      (warm.ink.computeLuminance() - cool.ink.computeLuminance()).abs(),
      lessThan(0.01),
    );
  });

  test('the accent presets keep their own hue and chroma', () {
    final teal = flvpAccentSpecs[FlvpAccent.teal]!;

    expect(
      flvpLightColors(FlvpAccent.teal).primary,
      flvpLightColorsOfHue(
        teal.hue,
        chromaFactor: teal.chromaFactor,
      ).primary,
    );
    expect(
      flvpDarkColors(FlvpAccent.teal).primary,
      flvpDarkColorsOfHue(
        teal.hue,
        chromaFactor: teal.chromaFactor,
      ).primary,
    );
  });

  test('pure black only darkens the dark palette', () {
    final normal = flvpDarkColorsOfHue(200);
    final black = flvpDarkColorsOfHue(200, pureBlack: true);

    expect(black.canvas, const Color(0xff000000));
    expect(black.surface, const Color(0xff0d0d0d));
    expect(black.dark, isTrue);
    expect(black.primary, normal.primary);
    expect(black.ink, normal.ink);
    expect(flvpLightColorsOfHue(200).canvas, isNot(const Color(0xff000000)));
  });
}
