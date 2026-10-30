import 'package:flutter/widgets.dart';

import '../design/motion.dart';

/// `animate-page`: fade in and rise 10 px over 320 ms when a page mounts.
class FlvpPageEntrance extends StatefulWidget {
  const FlvpPageEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<FlvpPageEntrance> createState() => _FlvpPageEntranceState();
}

class _FlvpPageEntranceState extends State<FlvpPageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FlvpMotion.page,
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: FlvpMotion.easeEntrance,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - _curve.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
