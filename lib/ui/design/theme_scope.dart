import 'package:flutter/widgets.dart';

import '../design/accents.dart';
import '../design/tokens.dart';

/// Provides the MD3 tonal tokens (the CSS custom properties of the design)
/// to the widget tree.
class FlvpThemeScope extends InheritedWidget {
  const FlvpThemeScope({
    super.key,
    required this.colors,
    required this.accent,
    required super.child,
  });

  final FlvpColors colors;
  final FlvpAccent accent;

  static FlvpThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlvpThemeScope>()!;

  static FlvpColors colorsOf(BuildContext context) => of(context).colors;

  @override
  bool updateShouldNotify(FlvpThemeScope oldWidget) =>
      !identical(oldWidget.colors, colors) || oldWidget.accent != accent;
}

/// The design's `font-mono` stack, resolved per platform by Flutter.
const List<String> flvpMonoFallback = ['Consolas', 'Courier New', 'monospace'];

/// Mirrors the utilities the design applies per text run (`text-[14.5px]`,
/// `font-medium`, `tabular-nums`, …).
TextStyle flvpText(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? letterSpacing,
  double? height,
  bool tabular = false,
  bool mono = false,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
  fontFamily: mono ? 'Consolas' : null,
  fontFamilyFallback: mono ? flvpMonoFallback : null,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

/// `MouseRegion` + hover state, replacing the design's CSS `:hover` rules.
/// Touch platforms simply never report hover, matching CSS behaviour.
class FlvpHover extends StatefulWidget {
  const FlvpHover({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<FlvpHover> createState() => _FlvpHoverState();
}

class _FlvpHoverState extends State<FlvpHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}
