import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import 'ripple.dart';
import 'surfaces.dart';

enum FlvpButtonVariant { filled, tonal, text, danger }

enum FlvpControlSize { sm, md }

/// `Button` from the design's ui.tsx (filled / tonal / text / danger).
class FlvpButton extends StatefulWidget {
  const FlvpButton({
    super.key,
    this.onPressed,
    this.variant = FlvpButtonVariant.filled,
    this.size = FlvpControlSize.md,
    this.icon,
    this.label,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final FlvpButtonVariant variant;
  final FlvpControlSize size;
  final Widget? icon;
  final String? label;
  final bool expand;

  @override
  State<FlvpButton> createState() => _FlvpButtonState();
}

class _FlvpButtonState extends State<FlvpButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final enabled = widget.onPressed != null;
    final (Color foreground, Color background) = switch (widget.variant) {
      FlvpButtonVariant.filled => (colors.onprimary, colors.primary),
      FlvpButtonVariant.tonal => (colors.onscontainer, colors.scontainer),
      FlvpButtonVariant.text => (colors.primary, const Color(0x00000000)),
      FlvpButtonVariant.danger => (
        colors.err,
        colors.err.withValues(alpha: 0.12),
      ),
    };
    final small = widget.size == FlvpControlSize.sm;
    final height = small ? 36.0 : 40.0;
    final horizontal = widget.variant == FlvpButtonVariant.text
        ? 12.0
        : (small ? 16.0 : 24.0);
    return FlvpHover(
      builder: (context, hovered) {
        final elevated =
            hovered &&
            (widget.variant == FlvpButtonVariant.filled ||
                widget.variant == FlvpButtonVariant.tonal);
        final fill = switch (widget.variant) {
          FlvpButtonVariant.text when hovered =>
            colors.primary.withValues(alpha: 0.10),
          FlvpButtonVariant.danger when hovered =>
            colors.err.withValues(alpha: 0.20),
          _ => background,
        };
        return Opacity(
          opacity: enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !enabled,
            child: FlvpRipple(
              color: foreground,
              borderRadius: BorderRadius.circular(999),
              child: GestureDetector(
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                onTap: widget.onPressed,
                child: AnimatedScale(
                  scale: _pressed ? 0.97 : 1,
                  duration: FlvpMotion.control,
                  child: AnimatedContainer(
                    duration: FlvpMotion.control,
                    height: height,
                    width: widget.expand ? double.infinity : null,
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: elevated ? FlvpElevation.card : null,
                    ),
                    child: IconTheme(
                      data: IconThemeData(color: foreground),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ?widget.icon,
                          if (widget.icon != null && widget.label != null)
                            const SizedBox(width: 8),
                          if (widget.label != null)
                            Text(
                              widget.label!,
                              style: flvpText(
                                small ? 13 : 14,
                                color: foreground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `IconButton` — 40x40 round state-layer button.
class FlvpIconButton extends StatelessWidget {
  const FlvpIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.label,
    this.active = false,
    this.dimension = 40,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool active;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final button = FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: active ? colors.onscontainer : colors.ink,
        borderRadius: BorderRadius.circular(999),
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: FlvpMotion.control,
            width: dimension,
            height: dimension,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? colors.scontainer
                  : (hovered ? colors.inkLayer() : const Color(0x00000000)),
            ),
            child: IconTheme(
              data: IconThemeData(
                color: active
                    ? colors.onscontainer
                    : (hovered ? colors.ink : colors.ink2),
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
    if (label == null) return button;
    return Tooltip(message: label!, child: button);
  }
}

/// MD3 Switch (52x32, icon thumb, grows while pressed). `data-noripple`.
class FlvpSwitch extends StatefulWidget {
  const FlvpSwitch({super.key, required this.value, this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  State<FlvpSwitch> createState() => _FlvpSwitchState();
}

class _FlvpSwitchState extends State<FlvpSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final on = widget.value;
    final enabled = widget.onChanged != null;
    final thumbSize = _pressed ? 28.0 : (on ? 24.0 : 16.0);
    final thumbLeft = _pressed ? (on ? 20.0 : 0.0) : (on ? 22.0 : 6.0);
    return Semantics(
      label: widget.label,
      toggled: on,
      button: true,
      child: FlvpHover(
        builder: (context, hovered) => Opacity(
          opacity: enabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () => widget.onChanged?.call(!on),
              child: AnimatedContainer(
                duration: FlvpMotion.control,
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: on ? colors.primary : colors.surf3,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: on
                        ? colors.primary
                        : colors.ink3.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      duration: FlvpMotion.control,
                      left: on ? 14 : -6,
                      top: -6,
                      child: AnimatedOpacity(
                        duration: FlvpMotion.control,
                        opacity: hovered ? 1 : 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on
                                ? colors.primary.withValues(alpha: 0.12)
                                : colors.ink.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: FlvpMotion.shape,
                      curve: FlvpMotion.easeSpring,
                      left: thumbLeft,
                      top: (28 - thumbSize) / 2,
                      child: AnimatedContainer(
                        duration: FlvpMotion.shape,
                        curve: FlvpMotion.easeSpring,
                        width: thumbSize,
                        height: thumbSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? colors.onprimary : colors.ink3,
                        ),
                        child: AnimatedOpacity(
                          duration: FlvpMotion.control,
                          opacity: on ? 1 : 0,
                          child: AnimatedScale(
                            duration: FlvpMotion.control,
                            scale: on ? 1 : 0.5,
                            child: FlvpIcon(
                              'Check',
                              size: 14,
                              strokeWidth: 3,
                              color: colors.primary,
                            ),
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
      ),
    );
  }
}

class FlvpSegmentedOption<T> {
  const FlvpSegmentedOption(this.value, this.label);

  final T value;
  final String label;
}

/// MD3 Expressive connected button group (shape morph on select).
class FlvpSegmented<T> extends StatelessWidget {
  const FlvpSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.size = FlvpControlSize.md,
    this.full = false,
  });

  final List<FlvpSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final FlvpControlSize size;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final small = size == FlvpControlSize.sm;
    final height = small ? 34.0 : 42.0;
    final bigRadius = height / 2;
    final smallRadius = small ? 7.0 : 9.0;
    final children = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      final selected = option.value == value;
      final first = i == 0;
      final last = i == options.length - 1;
      final radius = selected
          ? BorderRadius.circular(bigRadius)
          : BorderRadius.only(
              topLeft: Radius.circular(first ? bigRadius : smallRadius),
              topRight: Radius.circular(last ? bigRadius : smallRadius),
              bottomRight: Radius.circular(last ? bigRadius : smallRadius),
              bottomLeft: Radius.circular(first ? bigRadius : smallRadius),
            );
      final segment = FlvpHover(
        builder: (context, hovered) => FlvpRipple(
          color: selected ? colors.onprimary : colors.ink,
          borderRadius: radius,
          child: GestureDetector(
            onTap: () => onChanged(option.value),
            child: AnimatedContainer(
              duration: FlvpMotion.shape,
              curve: FlvpMotion.easeEmph,
              height: height,
              padding: EdgeInsets.symmetric(
                horizontal: full ? 8 : (small ? 16 : 20),
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary
                    : (hovered ? colors.surf3 : colors.surf2),
                borderRadius: radius,
              ),
              child: AnimatedDefaultTextStyle(
                duration: FlvpMotion.shape,
                curve: FlvpMotion.easeEmph,
                style: flvpText(
                  small ? 12.5 : 13.5,
                  color: selected
                      ? colors.onprimary
                      : (hovered ? colors.ink : colors.ink2),
                ),
                child: Text(option.label, maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ),
      );
      children.add(full ? Expanded(child: segment) : segment);
    }
    return Row(mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min, spacing: 3, children: children);
  }
}

/// `Field` — labelled text input with an inset focus ring.
class FlvpField extends StatefulWidget {
  const FlvpField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.mono = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final bool mono;

  @override
  State<FlvpField> createState() => _FlvpFieldState();
}

class _FlvpFieldState extends State<FlvpField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(FlvpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(widget.label, style: flvpText(12.5, color: colors.ink2)),
        ),
        AnimatedBuilder(
          animation: _focus,
          builder: (context, _) => AnimatedContainer(
            duration: FlvpMotion.control,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: colors.tile,
              borderRadius: BorderRadius.circular(14),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focus.hasFocus
                    ? colors.primary
                    : const Color(0x00000000),
                width: 2,
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              maxLines: 1,
              cursorColor: colors.primary,
              style: flvpText(
                widget.mono ? 13 : 14,
                weight: FontWeight.w400,
                color: colors.ink,
                mono: widget.mono,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: flvpText(
                  widget.mono ? 13 : 14,
                  weight: FontWeight.w400,
                  color: colors.ink3,
                  mono: widget.mono,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FlvpRadioOption<T> {
  const FlvpRadioOption(this.value, this.label, {this.description});

  final T value;
  final String label;
  final String? description;
}

/// `RadioList` — MD3 radio rows with a spring-scaled dot.
class FlvpRadioList<T> extends StatelessWidget {
  const FlvpRadioList({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<FlvpRadioOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      spacing: 2,
      children: [
        for (final option in options)
          FlvpHover(
            builder: (context, hovered) {
              final selected = option.value == value;
              return FlvpRipple(
                color: colors.ink,
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option.value),
                  child: AnimatedContainer(
                    duration: FlvpMotion.hover,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hovered
                          ? colors.ink.withValues(alpha: 0.05)
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: FlvpMotion.control,
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? colors.primary : colors.ink2,
                              width: 2,
                            ),
                          ),
                          child: AnimatedScale(
                            duration: FlvpMotion.shape,
                            curve: FlvpMotion.easeSpring,
                            scale: selected ? 1 : 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                option.label,
                                style: flvpText(14.5, color: colors.ink),
                              ),
                              if (option.description != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    option.description!,
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
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Settings.tsx `TileToggle` — a list item rendered as a tonal tile inside
/// dialogs (no hover change, `px-4`).
class FlvpTileToggle extends StatelessWidget {
  const FlvpTileToggle({
    super.key,
    required this.title,
    required this.summary,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String summary;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpRow(
      title: title,
      subtitle: summary,
      background: colors.tile,
      hoverBackground: colors.tile,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => onChanged(!value),
      trailing: FlvpSwitch(value: value, onChanged: onChanged, label: title),
    );
  }
}

/// `inline-flex h-8 items-center gap-2 rounded-[10px] bg-tile px-3 text-[13px]
/// font-medium text-ink2 hover:text-ink` — the paste button of the import
/// dialog.
class FlvpTileButton extends StatelessWidget {
  const FlvpTileButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: FlvpHover(
        builder: (context, hovered) => FlvpRipple(
          color: colors.ink,
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.tile,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  FlvpIcon(icon, size: 15, color: hovered ? colors.ink : colors.ink2),
                  Text(
                    label,
                    style: flvpText(13, color: hovered ? colors.ink : colors.ink2),
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
