import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';

/// The design's global MD3 ripple (state layer).
///
/// The design attaches a document-level listener that spawns one expanding
/// dot per press inside the pressed surface (`.ripple-host`/`.ripple-dot`:
/// 14% of `currentColor`, scale 0 -> 1 over 550 ms on cubic-bezier(0.2,0,0,1),
/// then a 400 ms fade-out held for at least 260 ms). [surface] reproduces
/// `data-ripple-in`: the dot is clipped to and measured from a child rect
/// (the navigation pill) instead of the whole host.
class FlvpRipple extends StatefulWidget {
  const FlvpRipple({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = BorderRadius.zero,
    this.surface,
  });

  final Widget child;
  final Color? color;
  final BorderRadius borderRadius;
  final Rect? surface;

  @override
  State<FlvpRipple> createState() => _FlvpRippleState();
}

class _FlvpRippleState extends State<FlvpRipple>
    with SingleTickerProviderStateMixin {
  final List<_RippleDot> _dots = [];
  Ticker? _ticker;

  void _ensureTicker() {
    _ticker ??= createTicker((_) => _frame());
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _frame() {
    final now = DateTime.now();
    var alive = false;
    for (final dot in _dots) {
      final expanded = now.difference(dot.start).inMicroseconds / 550000;
      final faded = dot.released == null
          ? 0.0
          : (now.difference(dot.released!).inMilliseconds -
                    FlvpMotion.rippleHold.inMilliseconds) /
                400;
      dot.fade = (1 - faded).clamp(0.0, 1.0);
      if (expanded < 1 || dot.fade > 0) alive = true;
    }
    _dots.removeWhere(
      (dot) =>
          now.difference(dot.start).inMicroseconds / 550000 >= 1 &&
          dot.fade <= 0,
    );
    setState(() {});
    if (!alive) {
      _ticker?.stop();
    }
  }

  void _down(PointerDownEvent event) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final surface =
        widget.surface ?? (Offset.zero & size);
    final position = event.localPosition;
    final radius = math.sqrt(
      math.pow(math.max(position.dx - surface.left, surface.right - position.dx), 2) +
          math.pow(math.max(position.dy - surface.top, surface.bottom - position.dy), 2),
    );
    _dots.add(_RippleDot(position, radius));
    _ensureTicker();
    setState(() {});
  }

  void _up([PointerEvent? event]) {
    final now = DateTime.now();
    for (final dot in _dots) {
      dot.released ??= now;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_dots.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RipplePainter(
                    dots: _dots,
                    color: widget.color ?? colors.ink,
                    borderRadius: widget.borderRadius,
                    surface: widget.surface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RippleDot {
  _RippleDot(this.origin, this.radius);

  final Offset origin;
  final double radius;
  final DateTime start = DateTime.now();
  DateTime? released;
  double fade = 1;
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.dots,
    required this.color,
    required this.borderRadius,
    this.surface,
  });

  final List<_RippleDot> dots;
  final Color color;
  final BorderRadius borderRadius;
  final Rect? surface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      surface != null
          ? RRect.fromRectAndRadius(surface!, const Radius.circular(999))
          : borderRadius.toRRect(Offset.zero & size),
    );
    final base = color;
    for (final dot in dots) {
      final t = (DateTime.now().difference(dot.start).inMicroseconds / 550000)
          .clamp(0.0, 1.0);
      final scale = FlvpMotion.easeEmph.transform(t);
      canvas.drawCircle(
        dot.origin,
        dot.radius * scale,
        Paint()..color = base.withValues(alpha: 0.14 * dot.fade),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => true;
}
