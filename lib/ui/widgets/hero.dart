import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';

/// `AppMark` — the brand mark: 30% rounded square with the indigo → violet
/// gradient and the orbit glyph.
class FlvpAppMark extends StatelessWidget {
  const FlvpAppMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff4c5bd4), Color(0xff8a5cf6)],
      ),
      borderRadius: BorderRadius.circular(size * 0.3),
      boxShadow: FlvpElevation.card,
    ),
    child: CustomPaint(painter: _AppMarkGlyphPainter(size)),
  );
}

class _AppMarkGlyphPainter extends CustomPainter {
  _AppMarkGlyphPainter(this.size);

  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // The glyph is a 24-grid SVG rendered at 62% of the mark.
    final glyph = size * 0.62;
    final scale = glyph / 24;
    canvas.save();
    canvas.translate((size - glyph) / 2, (size - glyph) / 2);
    canvas.scale(scale);
    const white = Color(0xffffffff);
    canvas.drawCircle(const Offset(12, 12), 3.1, Paint()..color = white);
    final stroke = Paint()
      ..color = white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..isAntiAlias = true;
    canvas.save();
    canvas.translate(12, 12);
    canvas.rotate(-28 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18.4, height: 8.2),
      stroke,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(12, 12);
    canvas.rotate(52 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18.4, height: 8.2),
      stroke..color = white.withValues(alpha: 0.55),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppMarkGlyphPainter oldDelegate) =>
      oldDelegate.size != size;
}

/// `PowerButton` — MD3 Expressive shape morph (circle ⇄ 9-lobe cookie).
///
/// The blob amplitude tweens 0 → 0.075 over 760 ms and the inner circle
/// 0.88 → 1 over 620 ms, both on the design's ease-out-back; the blob
/// rotates once every 26 s and freezes (`animation-play-state: paused`)
/// while the proxy is stopped.
class FlvpPowerButton extends StatefulWidget {
  const FlvpPowerButton({
    super.key,
    required this.running,
    required this.onToggle,
    this.size = 120,
  });

  final bool running;
  final VoidCallback onToggle;
  final double size;

  @override
  State<FlvpPowerButton> createState() => _FlvpPowerButtonState();
}

class _FlvpPowerButtonState extends State<FlvpPowerButton>
    with TickerProviderStateMixin {
  late final AnimationController _blob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
    value: widget.running ? 1 : 0,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: widget.running ? 1 : 0,
  );
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: FlvpMotion.spinSlow,
  );
  late final Animation<double> _amp = CurvedAnimation(
    parent: _blob,
    curve: const FlvpEaseOutBack(),
    reverseCurve: const FlvpEaseOutBack(),
  ).drive(Tween(begin: 0, end: 0.075));
  late final Animation<double> _scale = CurvedAnimation(
    parent: _pop,
    curve: const FlvpEaseOutBack(),
    reverseCurve: const FlvpEaseOutBack(),
  ).drive(Tween(begin: 0.88, end: 1));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.running) _rotation.repeat();
  }

  @override
  void didUpdateWidget(FlvpPowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      if (widget.running) {
        _blob.forward();
        _pop.forward();
        _rotation.repeat();
      } else {
        _blob.reverse();
        _pop.reverse();
        _rotation.stop();
      }
    }
  }

  @override
  void dispose() {
    _blob.dispose();
    _pop.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final size = widget.size;
    final running = widget.running;
    return Semantics(
      button: true,
      label: running ? '停止代理' : '启动代理',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1,
            duration: FlvpMotion.control,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_amp, _rotation]),
                    builder: (context, _) => Transform.rotate(
                      angle: _rotation.value * 2 * math.pi,
                      child: TweenAnimationBuilder<Color?>(
                        duration: const Duration(milliseconds: 500),
                        tween: ColorTween(
                          end: running ? colors.pcontainer : colors.surf2,
                        ),
                        builder: (context, fill, _) => CustomPaint(
                          size: Size.square(size),
                          painter: _BlobPainter(
                            amplitude: _amp.value,
                            color: fill ?? colors.surf2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scale,
                    builder: (context, child) => Transform.scale(
                      scale: _scale.value,
                      child: child,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: size * 0.6,
                      height: size * 0.6,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? colors.primary : colors.surf3,
                        boxShadow: running ? FlvpElevation.float : null,
                      ),
                      child: TweenAnimationBuilder<Color?>(
                        duration: const Duration(milliseconds: 500),
                        tween: ColorTween(
                          end: running ? colors.onprimary : colors.ink2,
                        ),
                        builder: (context, glyph, _) => CustomPaint(
                          size: Size.square(size * 0.24),
                          painter: _PowerGlyphPainter(glyph ?? colors.ink2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.amplitude, required this.color});

  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // blobPath(amp, lobes = 9, r = 43, steps = 180) on a 100x100 viewBox.
    final scale = size.width / 100;
    final path = Path();
    const steps = 180;
    for (var i = 0; i < steps; i++) {
      final t = (i / steps) * math.pi * 2;
      final rr = 43 * (1 + amplitude * math.cos(9 * t));
      final x = (50 + rr * math.cos(t)) * scale;
      final y = (50 + rr * math.sin(t)) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) =>
      oldDelegate.amplitude != amplitude || oldDelegate.color != color;
}

class _PowerGlyphPainter extends CustomPainter {
  _PowerGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // <path d="M12 3.5v7.5" /><path d="M7.4 6.6a7 7 0 1 0 9.2 0" /> on 24x24.
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawLine(const Offset(12, 3.5), const Offset(12, 11), paint);
    final arc = Path()
      ..moveTo(7.4, 6.6)
      ..arcToPoint(
        const Offset(16.6, 6.6),
        radius: const Radius.circular(7),
        largeArc: true,
        clockwise: false,
      );
    canvas.drawPath(arc, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PowerGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
