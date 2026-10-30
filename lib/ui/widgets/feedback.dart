import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../store/design_store.dart';
import 'controls.dart';

enum FlvpPlatform { pc, mobile }

/// The shells' overlay host, mirroring `ModalHostContext`: dialogs and sheets
/// render inside the window / phone screen, on top of the page and snackbar.
class FlvpModalHost extends StatefulWidget {
  const FlvpModalHost({super.key, required this.child});

  final Widget child;

  static FlvpModalHostState of(BuildContext context) =>
      context.findAncestorStateOfType<FlvpModalHostState>()!;

  @override
  State<FlvpModalHost> createState() => FlvpModalHostState();
}

class FlvpModalHostState extends State<FlvpModalHost> {
  WidgetBuilder? _builder;
  Object? _token;

  bool get isOpen => _builder != null;

  /// Shows [builder] until [close] is called. The design unmounts dialogs
  /// instantly on close (no exit animation), so closing is immediate.
  void show(WidgetBuilder builder) => setState(() {
    _builder = builder;
    _token = Object();
  });

  void close() {
    if (_builder == null) return;
    setState(() {
      _builder = null;
      _token = null;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_builder != null)
        Positioned.fill(
          key: ValueKey(_token),
          child: Builder(builder: _builder!),
        ),
    ],
  );
}

/// `Modal` — MD3 dialog on desktop, draggable bottom sheet on mobile.
class FlvpModal extends StatefulWidget {
  const FlvpModal({
    super.key,
    required this.platform,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.footer,
    required this.onClose,
  });

  final FlvpPlatform platform;
  final String title;
  final String? subtitle;
  final Widget? icon;
  final Widget child;
  final List<Widget>? footer;
  final VoidCallback onClose;

  @override
  State<FlvpModal> createState() => _FlvpModalState();
}

class _FlvpModalState extends State<FlvpModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: widget.platform == FlvpPlatform.pc
        ? FlvpMotion.pop
        : FlvpMotion.sheet,
  )..forward();
  double _drag = 0;
  bool _dragging = false;

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.platform == FlvpPlatform.pc
          ? _dialog(colors)
          : _sheet(colors),
    );
  }

  Widget _scrim(Color color, double opacity, Duration fade) => Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onClose,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _enter,
          curve: Interval(
            0,
            (fade.inMilliseconds / _enter.duration!.inMilliseconds).clamp(
              0.0,
              1.0,
            ),
            curve: Curves.easeOut,
          ),
        ),
        child: Opacity(opacity: opacity, child: ColoredBox(color: color)),
      ),
    ),
  );

  Widget _dialog(FlvpColors colors) {
    final centered = widget.icon != null;
    final pop = CurvedAnimation(parent: _enter, curve: FlvpMotion.easeEntrance);
    return Stack(
      children: [
        _scrim(const Color(0x4d000000), 1, FlvpMotion.fade),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: FadeTransition(
              opacity: pop,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(pop),
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.dialog,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: FlvpElevation.float,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.icon != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Center(child: widget.icon),
                        ),
                      Text(
                        widget.title,
                        textAlign: centered ? TextAlign.center : null,
                        style: flvpText(22, height: 1.2, color: colors.ink),
                      ),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            widget.subtitle!,
                            textAlign: centered ? TextAlign.center : null,
                            style: flvpText(
                              13.5,
                              weight: FontWeight.w400,
                              height: 1.625,
                              color: colors.ink2,
                            ),
                          ),
                        ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: FlvpThinScrollbar(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children:
                              widget.footer ??
                              [
                                FlvpButton(
                                  variant: FlvpButtonVariant.text,
                                  label: '完成',
                                  onPressed: widget.onClose,
                                ),
                              ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _endDrag() {
    if (_drag > 90) {
      widget.onClose();
      return;
    }
    setState(() {
      _dragging = false;
      _drag = 0;
    });
  }

  Widget _sheet(FlvpColors colors) {
    final centered = widget.icon != null;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          _scrim(
            const Color(0x59000000),
            1 - math.min(_drag / 400, 0.6),
            FlvpMotion.fade,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _enter, curve: FlvpMotion.easeEntrance),
              ),
              child: AnimatedContainer(
                duration: _dragging ? Duration.zero : FlvpMotion.shape,
                curve: FlvpMotion.easeEmph,
                transform: Matrix4.translationValues(0, _drag, 0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.88,
                  ),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 32),
                    decoration: BoxDecoration(
                      color: colors.dialog,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      boxShadow: FlvpElevation.float,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (_) =>
                              setState(() => _dragging = true),
                          onVerticalDragUpdate: (details) => setState(
                            () => _drag = math.max(0, _drag + details.delta.dy),
                          ),
                          onVerticalDragEnd: (_) => _endDrag(),
                          onVerticalDragCancel: _endDrag,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: colors.ink3.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                                if (widget.icon != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: Center(child: widget.icon),
                                  ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: centered ? 12 : 20,
                                  ),
                                  child: Text(
                                    widget.title,
                                    textAlign: centered
                                        ? TextAlign.center
                                        : null,
                                    style: flvpText(
                                      20,
                                      height: 1.2,
                                      color: colors.ink,
                                    ),
                                  ),
                                ),
                                if (widget.subtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      widget.subtitle!,
                                      textAlign: centered
                                          ? TextAlign.center
                                          : null,
                                      style: flvpText(
                                        13,
                                        weight: FontWeight.w400,
                                        color: colors.ink2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: widget.child,
                              ),
                            ),
                          ),
                        ),
                        if (widget.footer != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              spacing: 8,
                              children: widget.footer!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.sb-thin` — a 6 px rounded scrollbar in `surf3`, no track.
class FlvpThinScrollbar extends StatelessWidget {
  const FlvpThinScrollbar({super.key, required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: controller,
        thickness: 6,
        radius: const Radius.circular(99),
        thumbColor: colors.surf3,
        child: child,
      ),
    );
  }
}

/// `Snackbar` — MD3 snackbar anchored to the bottom of the shell.
class FlvpSnackbar extends StatefulWidget {
  const FlvpSnackbar({
    super.key,
    required this.toast,
    required this.onAction,
    required this.maxWidth,
  });

  final FlvpToast toast;
  final VoidCallback onAction;
  final double maxWidth;

  @override
  State<FlvpSnackbar> createState() => _FlvpSnackbarState();
}

class _FlvpSnackbarState extends State<FlvpSnackbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: FlvpMotion.toast,
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final action = widget.toast.action;
    final curve = CurvedAnimation(parent: _enter, curve: FlvpMotion.easeEntrance);
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 18 * (1 - curve.value)),
          child: Transform.scale(scale: 0.96 + 0.04 * curve.value, child: child),
        ),
        child: IgnorePointer(
          ignoring: action == null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 240,
              maxWidth: widget.maxWidth * 0.86,
            ),
            child: IntrinsicWidth(
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 6, action != null ? 6 : 16, 6),
                decoration: BoxDecoration(
                  color: colors.ink,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: FlvpElevation.float,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          widget.toast.message,
                          style: flvpText(
                            13.5,
                            weight: FontWeight.w400,
                            height: 1.375,
                            color: colors.canvas,
                          ),
                        ),
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(width: 8),
                      FlvpHover(
                        builder: (context, hovered) => GestureDetector(
                          onTap: widget.onAction,
                          child: AnimatedContainer(
                            duration: FlvpMotion.hover,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: hovered
                                  ? colors.canvas.withValues(alpha: 0.10)
                                  : const Color(0x00000000),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              action.label,
                              style: flvpText(
                                13.5,
                                weight: FontWeight.w600,
                                color: colors.invprimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
