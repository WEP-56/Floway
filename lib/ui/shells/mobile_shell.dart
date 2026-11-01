import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../nav.dart';
import '../pages/dashboard_page.dart';
import '../pages/add_profile_modal.dart';
import '../pages/info_page.dart';
import '../pages/nodes_page.dart';
import '../pages/settings_page.dart';
import '../pages/subscriptions_page.dart';
import '../store/design_store.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/page_entrance.dart';
import '../widgets/ripple.dart';

/// components/MobileApp.tsx — the phone screen: MD3 top app bar with
/// on-scroll elevation, large title, extended FAB and navigation bar.
///
/// [mock] draws the design's fake status bar and home indicator so the shell
/// can be compared 1:1 with the preview; the real app leaves those to the OS
/// and only reserves the system insets.
class FlvpMobileShell extends StatefulWidget {
  const FlvpMobileShell({
    super.key,
    this.mock = false,
    this.initialPage = FlvpPageKey.dashboard,
  });

  final bool mock;
  final FlvpPageKey initialPage;

  @override
  State<FlvpMobileShell> createState() => _FlvpMobileShellState();
}

class _FlvpMobileShellState extends State<FlvpMobileShell> {
  late FlvpPageKey _page = widget.initialPage;
  final ScrollController _scroll = ScrollController();
  double _scrollY = 0;
  final GlobalKey<FlvpModalHostState> _host = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final y = _scroll.offset;
      // Only the thresholds matter (> 4, > 24, > 44); avoid per-pixel rebuilds.
      if ((y > 4) != (_scrollY > 4) ||
          (y > 24) != (_scrollY > 24) ||
          (y > 44) != (_scrollY > 44)) {
        setState(() => _scrollY = y);
      } else {
        _scrollY = y;
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(FlvpPageKey page) {
    setState(() {
      _page = page;
      _scrollY = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openImport() {
    final host = _host.currentState!;
    host.show(
      (context) => FlvpAddProfileModal(
        platform: FlvpPlatform.mobile,
        onClose: host.close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final store = FlvpStoreScope.of(context);
    final padding = MediaQuery.paddingOf(context);
    final scrolled = _scrollY > 4;
    final collapsed = _scrollY > 44;
    final toast = store.toast;
    final statusHeight = widget.mock ? 44.0 : padding.top;
    final bottomInset = widget.mock ? 0.0 : padding.bottom;
    // 悬浮 dock：与屏幕边缘留出间距，内容从它下面穿过去。
    const dockHeight = 64.0;
    final dockBottom = 10 + (bottomInset > 0 ? bottomInset : 8.0);
    final dockTop = dockBottom + dockHeight;
    return FlvpModalHost(
      key: _host,
      child: LayoutBuilder(
        builder: (context, constraints) => ColoredBox(
          color: colors.canvas,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // status bar + top app bar share one container colour
                  AnimatedContainer(
                    duration: FlvpMotion.shape,
                    color: scrolled ? colors.frame : colors.canvas,
                    child: Column(
                      children: [
                        if (widget.mock)
                          _MockStatusBar(clock: fmtClock(store.clock))
                        else
                          SizedBox(height: statusHeight),
                        SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20, right: 8),
                            child: Row(
                              children: [
                                AnimatedSlide(
                                  duration: FlvpMotion.shape,
                                  curve: FlvpMotion.easeEmph,
                                  offset: collapsed
                                      ? Offset.zero
                                      : const Offset(0, 8 / 17),
                                  child: AnimatedOpacity(
                                    duration: FlvpMotion.shape,
                                    curve: FlvpMotion.easeEmph,
                                    opacity: collapsed ? 1 : 0,
                                    child: Text(
                                      flvpPageTitles[_page]!,
                                      style: flvpText(17, color: colors.ink),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (_page == FlvpPageKey.proxies)
                                  FlvpIconButton(
                                    label: '测试延迟',
                                    dimension: 40,
                                    onPressed: store.testNodes,
                                    icon: FlvpSpin(
                                      active: store.testing,
                                      child: const FlvpIcon('RefreshCw', size: 20),
                                    ),
                                  ),
                                if (_page == FlvpPageKey.profiles)
                                  FlvpIconButton(
                                    label: '更新全部订阅',
                                    dimension: 40,
                                    onPressed: store.refreshAllSubs,
                                    icon: const FlvpIcon('RefreshCw', size: 20),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // content — large title scrolls away, small title fades in
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(16, 0, 16, dockTop + 16),
                        child: FlvpPageEntrance(
                          key: ValueKey(_page),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                                child: Text(
                                  flvpPageTitles[_page]!,
                                  style: flvpText(
                                    26,
                                    height: 1.2,
                                    letterSpacing: -0.6,
                                    color: colors.ink,
                                  ),
                                ),
                              ),
                              switch (_page) {
                                FlvpPageKey.dashboard => FlvpDashboardPage(
                                  platform: FlvpPlatform.mobile,
                                  onNavigate: _go,
                                ),
                                FlvpPageKey.proxies => const FlvpNodesPage(platform: FlvpPlatform.mobile),
                                FlvpPageKey.profiles => const FlvpSubscriptionsPage(platform: FlvpPlatform.mobile),
                                FlvpPageKey.info => const FlvpInfoPage(
                                  platform: FlvpPlatform.mobile,
                                ),
                                FlvpPageKey.settings => FlvpSettingsPage(
                                  platform: FlvpPlatform.mobile,
                                  onNavigate: _go,
                                ),
                              },
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // MD3 extended FAB — shrinks while scrolling, moves up for snackbars
              if (_page == FlvpPageKey.profiles)
                AnimatedPositioned(
                  duration: FlvpMotion.fab,
                  curve: FlvpMotion.easeEmph,
                  right: 16,
                  bottom: dockTop + 12 + (toast != null ? 56 + 12 : 0),
                  child: _ExtendedFab(
                    collapsed: _scrollY > 24,
                    onTap: _openImport,
                  ),
                ),
              // 悬浮 dock：圆角、留白、投影，内容从下面穿过
              Positioned(
                left: 12,
                right: 12,
                bottom: dockBottom,
                child: _FloatingDock(
                  height: dockHeight,
                  items: flvpMobileNavItems,
                  isActive: (item) =>
                      _page == item.key ||
                      (item.key == FlvpPageKey.settings &&
                          _page == FlvpPageKey.info),
                  onTap: (item) => _go(item.key),
                ),
              ),
              if (widget.mock)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 7,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.ink.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              if (toast != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: dockTop + 12,
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
      ),
    );
  }
}

class _ExtendedFab extends StatelessWidget {
  const _ExtendedFab({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Semantics(
      button: true,
      label: '添加配置',
      child: FlvpRipple(
        color: colors.onpcontainer,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: FlvpMotion.fab,
            curve: FlvpMotion.easeEmph,
            height: 56,
            width: collapsed ? 56 : 136,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colors.pcontainer,
              borderRadius: BorderRadius.circular(16),
              boxShadow: FlvpElevation.float,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: FlvpIcon('Plus', size: 24, color: colors.onpcontainer),
                  ),
                ),
                AnimatedOpacity(
                  duration: FlvpMotion.control,
                  opacity: collapsed ? 0 : 1,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Text(
                      '添加配置',
                      maxLines: 1,
                      softWrap: false,
                      style: flvpText(14.5, color: colors.onpcontainer),
                    ),
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

/// 悬浮圆角 dock：与屏幕边缘留白、带投影，四项等宽。
class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.height,
    required this.items,
    required this.isActive,
    required this.onTap,
  });

  final double height;
  final List<FlvpNavItem> items;
  final bool Function(FlvpNavItem item) isActive;
  final ValueChanged<FlvpNavItem> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.dialog,
        borderRadius: BorderRadius.circular(26),
        boxShadow: FlvpElevation.float,
        border: Border.all(color: colors.hair),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _DockItem(
                key: ValueKey('nav-${item.key.name}'),
                icon: item.icon,
                label: item.label,
                active: isActive(item),
                onTap: () => onTap(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: FlvpRipple(
        color: active ? colors.onprimary : colors.ink,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // FlvpRipple 的 Stack 默认 topStart：不给 Center，整块内容会贴在
          // 槽位左侧，四个图标看起来就不居中了。
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
              AnimatedContainer(
                duration: FlvpMotion.shape,
                curve: FlvpMotion.easeEmph,
                width: 46,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? colors.primary : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: FlvpIcon(
                  icon,
                  size: 19,
                  strokeWidth: active ? 2.3 : 1.9,
                  color: active ? colors.onprimary : colors.ink2,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                style: flvpText(
                  10.5,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? colors.primary : colors.ink3,
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

/* ---------- preview-only status bar glyphs (MobileApp.tsx) ---------- */

class _MockStatusBar extends StatelessWidget {
  const _MockStatusBar({required this.clock});

  final String clock;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  clock,
                  style: flvpText(14, weight: FontWeight.w600, color: colors.ink, tabular: true),
                ),
                Row(
                  spacing: 6,
                  children: [
                    CustomPaint(size: const Size(17, 11), painter: _SignalPainter(colors.ink)),
                    CustomPaint(size: const Size(16, 11), painter: _WifiPainter(colors.ink)),
                    CustomPaint(size: const Size(25, 12), painter: _BatteryPainter(colors.ink)),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 94,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xff000000),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      final paint = Paint()..color = color.withValues(alpha: i == 3 ? 0.35 : 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 4.3, 8 - i * 2.4, 3, 3 + i * 2.4),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter oldDelegate) => oldDelegate.color != color;
}

class _WifiPainter extends CustomPainter {
  _WifiPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    // M1.5 3.6a10 10 0 0 1 13 0 / M4 6.3a6.4 6.4 0 0 1 8 0 / M6.7 8.9a2.6 2.6 0 0 1 2.6 0
    void arc(Offset from, Offset to, double r) {
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..arcToPoint(to, radius: Radius.circular(r), clockwise: true),
        paint,
      );
    }

    arc(const Offset(1.5, 3.6), const Offset(14.5, 3.6), 10);
    arc(const Offset(4, 6.3), const Offset(12, 6.3), 6.4);
    arc(const Offset(6.7, 8.9), const Offset(9.3, 8.9), 2.6);
  }

  @override
  bool shouldRepaint(_WifiPainter oldDelegate) => oldDelegate.color != color;
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0.5, 0.5, 21, 11), const Radius.circular(3.2)),
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2, 2, 15, 8), const Radius.circular(2)),
      Paint()..color = color,
    );
    canvas.drawPath(
      Path()
        ..moveTo(23.5, 4)
        ..lineTo(23.5, 8)
        ..arcToPoint(const Offset(23.5, 4), radius: const Radius.circular(2.2), clockwise: false)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) => oldDelegate.color != color;
}
