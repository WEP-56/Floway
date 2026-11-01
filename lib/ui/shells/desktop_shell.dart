import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window/window.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../nav.dart';
import '../pages/dashboard_page.dart';
import '../pages/import_sub_modal.dart';
import '../pages/info_page.dart';
import '../pages/nodes_page.dart';
import '../pages/settings_page.dart';
import '../pages/subscriptions_page.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/page_entrance.dart';
import '../widgets/ripple.dart';

/// components/DesktopApp.tsx — window caption, MD3 Expressive navigation
/// rail and the rounded content pane.
///
/// [framed] draws the design's preview chrome (22 px rounded frame,
/// `--shadow-win`, 1 px ring) around the shell; the real window relies on the
/// OS for that and runs frameless with this caption as its title bar.
class FlvpDesktopShell extends StatefulWidget {
  const FlvpDesktopShell({
    super.key,
    this.framed = false,
    this.initialPage = FlvpPageKey.dashboard,
  });

  final bool framed;
  final FlvpPageKey initialPage;

  @override
  State<FlvpDesktopShell> createState() => _FlvpDesktopShellState();
}

class _FlvpDesktopShellState extends State<FlvpDesktopShell> {
  late FlvpPageKey _page = widget.initialPage;
  bool _expanded = true;
  bool _manual = false;
  final GlobalKey<FlvpModalHostState> _host = GlobalKey();

  /// Shared by the page scroll view and its scrollbar: a [RawScrollbar] without
  /// an attached position throws on hover/wheel, so both must use this one.
  final ScrollController _paneScroll = ScrollController();

  bool get _windowControls => !kIsWeb && Platform.isWindows && !widget.framed;

  @override
  void dispose() {
    _paneScroll.dispose();
    super.dispose();
  }

  void _toggleRail(bool current) => setState(() {
    _manual = true;
    _expanded = !current;
  });

  Future<void> _window(Future<void> Function() action) async {
    if (!_windowControls) return;
    try {
      await action();
    } catch (error) {
      debugPrint('floway: window action failed: $error');
    }
  }

  Future<void> _toggleMaximize() => _window(() async {
    if (await desktopWindow.isMaximized()) {
      await desktopWindow.unmaximize();
    } else {
      await desktopWindow.maximize();
    }
  });

  void _openImport() {
    final host = _host.currentState!;
    host.show(
      (context) =>
          FlvpImportSubModal(platform: FlvpPlatform.pc, onClose: host.close),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final shell = LayoutBuilder(
      builder: (context, constraints) {
        // Adaptive layout: the rail collapses automatically on narrow
        // windows until the user toggles it (ResizeObserver, >= 900 px).
        final expanded = _manual ? _expanded : constraints.maxWidth >= 900;
        return FlvpModalHost(
          key: _host,
          child: ColoredBox(
            color: colors.frame,
            child: Column(
              children: [
                _caption(colors),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _rail(colors, expanded),
                      Expanded(child: _pane(colors)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!widget.framed) return shell;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          ...FlvpElevation.window,
          BoxShadow(
            color: colors.dark
                ? const Color(0x0dffffff)
                : const Color(0x0d000000),
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: shell,
    );
  }

  Widget _caption(FlvpColors colors) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: (_) => _window(desktopWindow.startDragging),
    onDoubleTap: _toggleMaximize,
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          const Spacer(),
          Text(
            'Floway',
            style: flvpText(12, letterSpacing: 0.3, color: colors.ink3),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _CaptionButton(
                  label: '最小化',
                  icon: const FlvpIcon('Minus', size: 15),
                  onTap: () => _window(desktopWindow.minimize),
                ),
                _CaptionButton(
                  label: '最大化',
                  icon: const FlvpIcon('Square', size: 11.5),
                  onTap: _toggleMaximize,
                ),
                _CaptionButton(
                  label: '关闭',
                  icon: const FlvpIcon('X', size: 15),
                  close: true,
                  onTap: () => _window(desktopWindow.close),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _rail(FlvpColors colors, bool expanded) {
    final store = FlvpStoreScope.of(context);
    final dark = store.resolvedDark;
    final width = expanded ? 224.0 : 96.0;
    return AnimatedContainer(
      duration: FlvpMotion.rail,
      curve: FlvpMotion.easeEmph,
      width: width,
      padding: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FlvpHover(
                  builder: (context, hovered) => Tooltip(
                    message: expanded ? '收起侧边栏' : '展开侧边栏',
                    child: FlvpRipple(
                      color: colors.ink,
                      borderRadius: BorderRadius.circular(999),
                      child: GestureDetector(
                        onTap: () => _toggleRail(expanded),
                        child: AnimatedContainer(
                          duration: FlvpMotion.hover,
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hovered
                                ? colors.inkLayer()
                                : const Color(0x00000000),
                          ),
                          child: FlvpIcon(
                            expanded ? 'PanelLeftClose' : 'PanelLeftOpen',
                            size: 22,
                            strokeWidth: 1.9,
                            color: hovered ? colors.ink : colors.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in flvpNavItems)
            _RailItem(
              key: ValueKey('nav-${item.key.name}'),
              icon: item.icon,
              label: item.label,
              active: _page == item.key,
              expanded: expanded,
              width: width,
              onTap: () => setState(() => _page = item.key),
            ),
          const Spacer(),
          _RailItem(
            key: const ValueKey('nav-theme'),
            icon: dark ? 'Sun' : 'Moon',
            label: dark ? '浅色模式' : '深色模式',
            shortLabel: dark ? '浅色' : '深色',
            expanded: expanded,
            width: width,
            onTap: store.toggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _pane(FlvpColors colors) {
    final store = FlvpStoreScope.of(context);
    final toast = store.toast;
    final Widget? actions = switch (_page) {
      FlvpPageKey.dashboard => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: FlvpElevation.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                FlvpIcon('Globe', size: 15, color: colors.ink3),
                Text('系统代理', style: flvpText(13, color: colors.ink)),
                FlvpSwitch(
                  value: store.settings.systemProxy,
                  label: '系统代理',
                  onChanged: (v) =>
                      store.setSettings((c) => c.copyWith(systemProxy: v)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: FlvpElevation.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                  FlvpIcon('Network', size: 15, color: colors.ink3),
                Text('TUN', style: flvpText(13, color: colors.ink)),
                FlvpSwitch(
                  value: store.settings.tunMode,
                  label: 'TUN 模式',
                  onChanged: (v) =>
                      store.setSettings((c) => c.copyWith(tunMode: v)),
                ),
              ],
            ),
          ),
        ],
      ),
      FlvpPageKey.proxies => FlvpButton(
        variant: FlvpButtonVariant.tonal,
        size: FlvpControlSize.sm,
        icon: FlvpSpin(
          active: store.testing,
          child: const FlvpIcon('Zap', size: 15),
        ),
        label: store.testing ? '测试中…' : '测试延迟',
        onPressed: store.testing ? null : store.testNodes,
      ),
      FlvpPageKey.profiles => FlvpButton(
        size: FlvpControlSize.sm,
        icon: const FlvpIcon('Plus', size: 16),
        label: '导入订阅',
        onPressed: _openImport,
      ),
      FlvpPageKey.info => null,
      FlvpPageKey.settings => null,
    };

    return Container(
      margin: const EdgeInsets.only(right: 12, bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Row(
                      children: [
                        Text(
                          flvpPageTitles[_page]!,
                          style: flvpText(
                            24,
                            letterSpacing: -0.6,
                            color: colors.ink,
                          ),
                        ),
                        const Spacer(),
                        ?actions,
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ShaderMask(
                    // `.fade-top`: mask-image linear-gradient(transparent 0, #000 16px)
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Color(0x00000000), Color(0xff000000)],
                      stops: [0, (16 / bounds.height).clamp(0.0, 1.0)],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: FlvpThinScrollbar(
                      controller: _paneScroll,
                      child: SingleChildScrollView(
                        controller: _paneScroll,
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: FlvpPageEntrance(
                          key: ValueKey(_page),
                          child: switch (_page) {
                            FlvpPageKey.dashboard => FlvpDashboardPage(
                              platform: FlvpPlatform.pc,
                              onNavigate: (page) =>
                                  setState(() => _page = page),
                            ),
                            FlvpPageKey.proxies => const FlvpNodesPage(
                              platform: FlvpPlatform.pc,
                            ),
                            FlvpPageKey.profiles => const FlvpSubscriptionsPage(
                              platform: FlvpPlatform.pc,
                            ),
                            FlvpPageKey.info => const FlvpInfoPage(),
                            FlvpPageKey.settings => const FlvpSettingsPage(
                              platform: FlvpPlatform.pc,
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (toast != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Center(
                  child: FlvpSnackbar(
                    key: ValueKey(toast.id),
                    toast: toast,
                    maxWidth: constraints.maxWidth,
                    onAction: () {
                      toast.action?.run();
                      store.dismissToast();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.close = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: FlvpMotion.hover,
            width: 48,
            height: 40,
            alignment: Alignment.center,
            color: hovered
                ? (close ? const Color(0xffc42b1c) : colors.inkLayer())
                : const Color(0x00000000),
            child: IconTheme(
              data: IconThemeData(
                color: hovered
                    ? (close ? const Color(0xffffffff) : colors.ink)
                    : colors.ink2,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// MD3 Expressive navigation rail item.
/// Collapsed: 56×32 pill indicator with the label below.
/// Expanded:  full-width 56 px pill with the label inline.
/// The icon keeps the same x position, so the morph stays smooth.
class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    this.shortLabel,
    this.active = false,
    required this.expanded,
    required this.width,
    required this.onTap,
  });

  final String icon;
  final String label;
  final String? shortLabel;
  final bool active;
  final bool expanded;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final indicator = expanded
        ? Rect.fromLTRB(12, 2, width - 12, 58)
        : Rect.fromLTRB(20, 4, width - 20, 36);
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: active ? colors.onscontainer : colors.ink,
        surface: indicator,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Semantics(
            button: true,
            selected: active,
            label: label,
            child: AnimatedContainer(
              duration: FlvpMotion.rail,
              curve: FlvpMotion.easeEmph,
              height: expanded ? 60 : 72,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: FlvpMotion.rail,
                    curve: FlvpMotion.easeEmph,
                    left: indicator.left,
                    top: indicator.top,
                    width: indicator.width,
                    height: indicator.height,
                    child: AnimatedContainer(
                      duration: FlvpMotion.rail,
                      curve: FlvpMotion.easeEmph,
                      decoration: BoxDecoration(
                        color: active
                            ? colors.scontainer
                            : (hovered
                                  ? colors.ink.withValues(alpha: 0.06)
                                  : const Color(0x00000000)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: FlvpMotion.rail,
                    curve: FlvpMotion.easeEmph,
                    left: 36,
                    top: expanded ? 18 : 8,
                    width: 24,
                    height: 24,
                    child: Center(
                      child: FlvpIcon(
                        icon,
                        size: 22,
                        strokeWidth: active ? 2.3 : 1.9,
                        color: active ? colors.onscontainer : colors.ink2,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 42,
                    child: AnimatedOpacity(
                      duration: expanded
                          ? const Duration(milliseconds: 100)
                          : FlvpMotion.rail,
                      curve: expanded ? Curves.linear : const Interval(0.4, 1),
                      opacity: expanded ? 0 : 1,
                      child: Text(
                        shortLabel ?? label,
                        textAlign: TextAlign.center,
                        style: flvpText(
                          12,
                          weight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active ? colors.ink : colors.ink2,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 72,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: expanded
                            ? FlvpMotion.rail
                            : const Duration(milliseconds: 100),
                        curve: expanded
                            ? const Interval(0.4, 1)
                            : Curves.linear,
                        opacity: expanded ? 1 : 0,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: flvpText(
                            14,
                            weight: active ? FontWeight.w600 : FontWeight.w500,
                            color: active ? colors.onscontainer : colors.ink2,
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
    );
  }
}
