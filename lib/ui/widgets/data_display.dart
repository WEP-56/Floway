import 'dart:math' as math;

import 'package:floway/common/constant.dart' show delayTimedOutValue;
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';

enum FlvpSparklineTone { primary, ok }

enum FlvpProgressTone { primary, warn }

/// `Sparkline` — smooth cubic line + gradient area on a 100x32 viewBox with
/// `preserveAspectRatio="none"` and a non-scaling 2 px stroke.
class FlvpSparkline extends StatelessWidget {
  const FlvpSparkline({
    super.key,
    required this.data,
    this.tone = FlvpSparklineTone.primary,
    this.height = 34,
  });

  final List<double> data;
  final FlvpSparklineTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          color: tone == FlvpSparklineTone.primary ? colors.primary : colors.ok,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.color});

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final max = math.max(data.reduce(math.max), 1.0);
    final sx = size.width / 100;
    final sy = size.height / 32;
    final points = [
      for (var i = 0; i < data.length; i++)
        Offset(
          i / (data.length - 1) * 100 * sx,
          (30 - (data[i] / max) * 25 - 2) * sy,
        ),
    ];
    final line = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final cx = (p0.dx + p1.dx) / 2;
      line.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    final area = Path.from(line)
      ..lineTo(100 * sx, 32 * sy)
      ..lineTo(0, 32 * sy)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0),
          ],
        ).createShader(area.getBounds()),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.data, data);
}

/// `animate-breathe`: opacity 0.5 -> 1 -> 0.5 over 2 s, ease-in-out.
class FlvpBreathe extends StatefulWidget {
  const FlvpBreathe({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<FlvpBreathe> createState() => _FlvpBreatheState();
}

class _FlvpBreatheState extends State<FlvpBreathe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: 0.5 + Curves.easeInOut.transform(_controller.value) * 0.5,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// `LatencyBadge` — colour-coded latency with a dot; breathes while testing.
class FlvpLatencyBadge extends StatelessWidget {
  const FlvpLatencyBadge({super.key, required this.ms, this.testing = false});

  final int? ms;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final value = ms;
    if (value == null) {
      return FlvpBreathe(
        active: testing,
        child: Text(
          testing ? '测试中' : '—',
          style: flvpText(12.5, color: colors.ink3),
        ),
      );
    }
    // 上游用负数表示没测出来：-1 是超时，其余是失败，都不该显示成正常延迟。
    if (value <= 0) {
      final tone = value == delayTimedOutValue ? colors.warn : colors.err;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
          ),
          const SizedBox(width: 6),
          Text(
            value == delayTimedOutValue ? '超时' : '失败',
            style: flvpText(12.5, weight: FontWeight.w600, color: tone),
          ),
        ],
      );
    }
    final tone = value < 100
        ? colors.ok
        : value < 200
        ? colors.warn
        : colors.err;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
        ),
        const SizedBox(width: 6),
        Text(
          '$value ms',
          style: flvpText(
            12.5,
            weight: FontWeight.w600,
            color: tone,
            tabular: true,
          ),
        ),
      ],
    );
  }
}

/// MD3 (2024) linear progress — gap between indicator and track + stop dot.
class FlvpProgressBar extends StatelessWidget {
  const FlvpProgressBar({
    super.key,
    required this.value,
    this.tone = FlvpProgressTone.primary,
  });

  final double value;
  final FlvpProgressTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final color = tone == FlvpProgressTone.warn ? colors.warn : colors.primary;
    final trackColor = tone == FlvpProgressTone.warn
        ? colors.warn.withValues(alpha: 0.20)
        : colors.primary.withValues(alpha: 0.15);
    final pct = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 5.0;
          final total = constraints.maxWidth;
          final indicator = (pct * total)
              .clamp(6.0, math.max(6.0, total - gap - 6))
              .toDouble();
          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: FlvpMotion.easeEmph,
                width: indicator,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Container(
                  height: 6,
                  constraints: const BoxConstraints(minWidth: 6),
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 1),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// MD3 Expressive wavy indeterminate progress (`.wavy-progress`): a primary
/// bar masked by a repeating 24x10 wave (stroke 3) that slides 24 px / 0.8 s.
class FlvpWavyProgress extends StatefulWidget {
  const FlvpWavyProgress({super.key});

  @override
  State<FlvpWavyProgress> createState() => _FlvpWavyProgressState();
}

class _FlvpWavyProgressState extends State<FlvpWavyProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FlvpMotion.wave,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return SizedBox(
      height: 10,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _WavePainter(
            color: colors.primary,
            phase: _controller.value * 24,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(99)),
    );
    canvas.translate(phase, 0);
    final wave = Path()..moveTo(-24, 5);
    var k = 0;
    for (var x = -24.0; x < size.width + 24; x += 12) {
      wave.quadraticBezierTo(x + 6, k.isEven ? 1.5 : 8.5, x + 12, 5);
      k++;
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

/// MD3 circular indeterminate progress (`.spinner`): 1.2 s rotation plus the
/// 1.4 s `flvp-dash` keyframes on a r=9 circle, stroke 2.6.
class FlvpSpinner extends StatefulWidget {
  const FlvpSpinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  State<FlvpSpinner> createState() => _FlvpSpinnerState();
}

class _FlvpSpinnerState extends State<FlvpSpinner>
    with TickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: FlvpMotion.spin,
  )..repeat();
  late final AnimationController _dash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    _dash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_rotation, _dash]),
        builder: (context, _) => Transform.rotate(
          angle: _rotation.value * 2 * math.pi,
          child: CustomPaint(
            painter: _SpinnerPainter(
              color: widget.color ?? colors.primary,
              progress: _dash.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // flvp-dash: 0% (2, offset 0) -> 50% (42, -10) -> 100% (42, -55)
    final double dash;
    final double offset;
    if (progress < 0.5) {
      final q = Curves.easeInOut.transform(progress / 0.5);
      dash = 2 + 40 * q;
      offset = -10 * q;
    } else {
      final q = Curves.easeInOut.transform((progress - 0.5) / 0.5);
      dash = 42;
      offset = -10 - 45 * q;
    }
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9));
    final metric = circle.computeMetrics().first;
    final length = metric.length;
    var start = (-offset) % length;
    final end = start + math.min(dash, length);
    final segment = Path();
    if (end <= length) {
      segment.addPath(metric.extractPath(start, end), Offset.zero);
    } else {
      segment.addPath(metric.extractPath(start, length), Offset.zero);
      segment.addPath(metric.extractPath(0, end - length), Offset.zero);
    }
    start = 0;
    canvas.drawPath(
      segment,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Tailwind `animate-spin`: one clockwise turn per second, linear.
class FlvpSpin extends StatefulWidget {
  const FlvpSpin({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<FlvpSpin> createState() => _FlvpSpinState();
}

class _FlvpSpinState extends State<FlvpSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(FlvpSpin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: widget.child,
  );
}
