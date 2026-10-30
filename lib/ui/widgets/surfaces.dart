import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import 'ripple.dart';

/// `Card` from the design's ui.tsx: `rounded-[24px] bg-surface shadow-card`.
class FlvpCard extends StatelessWidget {
  const FlvpCard({
    super.key,
    this.child,
    this.padding,
    this.color,
    this.radius = 24,
    this.shadow,
    this.hoverShadow,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double radius;
  final List<BoxShadow>? shadow;
  final List<BoxShadow>? hoverShadow;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      builder: (context, hovered) {
        final content = AnimatedContainer(
          duration: FlvpMotion.shape,
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? colors.surface,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: hovered ? (hoverShadow ?? shadow ?? FlvpElevation.card) : (shadow ?? FlvpElevation.card),
          ),
          child: child,
        );
        if (onTap == null) return content;
        return FlvpRipple(
          color: colors.ink,
          borderRadius: BorderRadius.circular(radius),
          child: GestureDetector(onTap: onTap, child: content),
        );
      },
    );
  }
}

/// MD3 list sub-header — primary colored, Android settings style.
class FlvpSectionLabel extends StatelessWidget {
  const FlvpSectionLabel({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final label = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title,
        style: flvpText(13, weight: FontWeight.w600, color: colors.primary),
      ),
    );
    if (trailing == null) return label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: flvpText(13, weight: FontWeight.w600, color: colors.primary),
            ),
          ),
          trailing!,
        ],
      ),
    );
  }
}

/// `Row` from the design's ui.tsx — the MD3 settings list item.
class FlvpRow extends StatelessWidget {
  const FlvpRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.background,
    this.hoverBackground,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
  });

  final Widget? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final Color? background;
  final Color? hoverBackground;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final interactive = onTap != null;
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: colors.ink,
        borderRadius: BorderRadius.circular(radius),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: FlvpMotion.hover,
            padding: padding,
            decoration: BoxDecoration(
              color: hovered && interactive
                  ? (hoverBackground ?? colors.inkHover())
                  : background,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: danger
                          ? colors.err.withValues(alpha: 0.12)
                          : colors.surf2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconTheme(
                      data: IconThemeData(
                        color: danger ? colors.err : colors.ink2,
                        size: 19,
                      ),
                      child: icon!,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          14.5,
                          color: danger ? colors.err : colors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: flvpText(
                              12.5,
                              weight: FontWeight.w400,
                              color: colors.ink2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Kbd` — the keyboard key cap with `--shadow-key`.
class FlvpKbd extends StatelessWidget {
  const FlvpKbd({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      height: 28,
      constraints: const BoxConstraints(minWidth: 28),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surf2,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: colors.hair, offset: const Offset(0, 1))],
      ),
      child: Text(
        label,
        style: flvpText(11.5, weight: FontWeight.w600, color: colors.ink2),
      ),
    );
  }
}

/// `StatusPill` — running indicator with a breathing dot.
class FlvpStatusPill extends StatefulWidget {
  const FlvpStatusPill({super.key, required this.running});

  final bool running;

  @override
  State<FlvpStatusPill> createState() => _FlvpStatusPillState();
}

class _FlvpStatusPillState extends State<FlvpStatusPill>
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
    final colors = FlvpThemeScope.colorsOf(context);
    return AnimatedContainer(
      duration: FlvpMotion.shape,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: widget.running
            ? colors.ok.withValues(alpha: 0.12)
            : colors.surf2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Opacity(
              opacity: widget.running
                  ? 0.5 + Curves.easeInOut.transform(_controller.value) * 0.5
                  : 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.running ? colors.ok : colors.ink3,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.running ? '运行中' : '已停止',
            style: flvpText(
              12.5,
              weight: FontWeight.w600,
              color: widget.running ? colors.ok : colors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Chip` — the MD3 filter chip.
class FlvpChip extends StatelessWidget {
  const FlvpChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: selected ? colors.onscontainer : colors.ink,
        borderRadius: BorderRadius.circular(10),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: FlvpMotion.control,
            height: 32,
            padding: EdgeInsets.only(
              left: selected ? 8 : 12,
              right: 12,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.scontainer : colors.surf2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  FlvpIcon('Check', size: 15, strokeWidth: 2.6, color: colors.onscontainer),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: flvpText(
                    13,
                    color: selected
                        ? colors.onscontainer
                        : (hovered ? colors.ink : colors.ink2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
