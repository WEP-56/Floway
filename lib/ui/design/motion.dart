import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Motion constants transcribed from the design's src/index.css keyframes.
abstract final class FlvpMotion {
  /// `--ease-emph: cubic-bezier(0.2, 0, 0, 1)`
  static const easeEmph = Cubic(0.2, 0, 0, 1);

  /// `--ease-spring: cubic-bezier(0.34, 1.45, 0.64, 1)`
  static const easeSpring = Cubic(0.34, 1.45, 0.64, 1);

  /// Shared by the sheet, pop, toast and page entrances:
  /// cubic-bezier(0.05, 0.7, 0.1, 1).
  static const easeEntrance = Cubic(0.05, 0.7, 0.1, 1);

  /// Ease-out-back used by the power blob tween and the radio dot.
  static const easeOutBack = Cubic(0.34, 1.56, 0.64, 1);

  static const sheet = Duration(milliseconds: 380);
  static const pop = Duration(milliseconds: 280);
  static const fade = Duration(milliseconds: 220);
  static const toast = Duration(milliseconds: 320);
  static const page = Duration(milliseconds: 320);
  static const rail = Duration(milliseconds: 500);
  static const breathe = Duration(seconds: 2);
  static const spinSlow = Duration(seconds: 26);
  static const spin = Duration(milliseconds: 1200);
  static const ripple = Duration(milliseconds: 550);
  static const rippleFade = Duration(milliseconds: 400);
  static const rippleHold = Duration(milliseconds: 260);
  static const wave = Duration(milliseconds: 800);
  static const hover = Duration(milliseconds: 150);
  static const control = Duration(milliseconds: 200);
  static const shape = Duration(milliseconds: 300);
  static const fab = Duration(milliseconds: 300);
}

/// The design's `useTween` easing: `1 + (c1 + 1) * (p - 1)^3 + c1 * (p - 1)^2`
/// with `c1 = 1.4`. Used by the power button blob and its inner circle.
class FlvpEaseOutBack extends Curve {
  const FlvpEaseOutBack([this.c1 = 1.4]);

  final double c1;

  @override
  double transformInternal(double t) {
    final c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}
