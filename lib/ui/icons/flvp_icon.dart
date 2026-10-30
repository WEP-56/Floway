import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'flvp_icons.dart';

/// Renders the generated lucide 1.64.0 geometry on the same 24x24 grid.
///
/// Matches lucide-react's rendering contract: stroke-only paths, round caps
/// and joins, and a stroke width given in grid units so the rendered width
/// is `strokeWidth * size / 24`, exactly like the SVG `stroke-width`.
class FlvpIcon extends StatelessWidget {
  const FlvpIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.strokeWidth = 2,
    this.color,
  });

  final String name;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final data = flvpIconPaths[name];
    assert(data != null, 'Unknown icon "$name"');
    final resolved =
        color ?? IconTheme.of(context).color ?? const Color(0xff000000);
    return CustomPaint(
      size: Size.square(size),
      painter: _FlvpIconPainter(
        data == null ? Path() : flvpIconPath(data),
        strokeWidth,
        resolved,
        size,
      ),
    );
  }
}

final Map<String, Path> _pathCache = {};

/// Parses the generated subset (absolute M/L/C/Q/Z on the 24x24 grid).
/// Results are cached: icon paths are shared between every instance.
Path flvpIconPath(String data) => _pathCache.putIfAbsent(data, () {
  final path = Path();
  final tokens = data
      .split(RegExp(r'[\s,]+'))
      .where((token) => token.isNotEmpty)
      .toList();
  var i = 0;
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double take() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final command = tokens[i++];
    if (command == 'M') {
      x = take();
      y = take();
      path.moveTo(x, y);
      sx = x;
      sy = y;
    } else if (command == 'L') {
      x = take();
      y = take();
      path.lineTo(x, y);
    } else if (command == 'C') {
      final x1 = take(), y1 = take();
      final x2 = take(), y2 = take();
      x = take();
      y = take();
      path.cubicTo(x1, y1, x2, y2, x, y);
    } else if (command == 'Q') {
      final x1 = take(), y1 = take();
      x = take();
      y = take();
      path.quadraticBezierTo(x1, y1, x, y);
    } else if (command == 'Z') {
      path.close();
      x = sx;
      y = sy;
    } else {
      throw FormatException('Unexpected icon path command "$command"');
    }
  }
  return path;
});

class _FlvpIconPainter extends CustomPainter {
  _FlvpIconPainter(this.path, this.strokeWidth, this.color, this.size);

  final ui.Path path;
  final double strokeWidth;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.scale(size / 24);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlvpIconPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color ||
      oldDelegate.size != size;
}
