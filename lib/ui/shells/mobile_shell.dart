import 'package:material_ui/material_ui.dart';

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
      (context) => FlvpImportSubModal(
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
    final navHeight = 80 + (bottomInset > 6 ? bottomInset : 6.0);

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
                          height: 56,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20, right: 8),
                            child: Row(
                              children: [
                                AnimatedSlide(
                                  duration: FlvpMotion.shape,
                                  curve: FlvpMotion.easeEmph,
                                  offset: collapsed ? Offset.zero : const Offset(0, 8 / 19),
                                  child: AnimatedOpacity(
                                    duration: FlvpMotion.shape,
                                    curve: FlvpMotion.easeEmph,
                                    opacity: collapsed ? 1 : 0,
                                    child: Text(
                                      flvpPageTitles[_page]!,
                                      style: flvpText(19, color: colors.ink),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (_page == FlvpPageKey.proxies)
                                  FlvpIconButton(
                                    label: '测试延迟',
                                    dimension: 44,
                                    onPressed: store.testNodes,
                                    icon: FlvpSpin(
                                      active: store.testing,
                                      child: const FlvpIcon('RefreshCw', size: 20),
                                    ),
                                  ),
                                if (_page == FlvpPageKey.profiles)
                                  FlvpIconButton(
                                    label: '更新全部订阅',
                                    dimension: 44,
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 124),
                        child: FlvpPageEntrance(
                          key: ValueKey(_page),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
                                child: Text(
                                  flvpPageTitles[_page]!,
                                  style: flvpText(32, height: 1.25, letterSpacing: -0.8, color: colors.ink),
                                ),
                              ),
                              switch (_page) {
                                FlvpPageKey.dashboard => FlvpDashboardPage(
                                  platform: FlvpPlatform.mobile,
                                  onNavigate: _go,
                                ),
                                FlvpPageKey.proxies => const FlvpNodesPage(platform: FlvpPlatform.mobile),
                                FlvpPageKey.profiles => const FlvpSubscriptionsPage(platform: FlvpPlatform.mobile),
                                FlvpPageKey.info => const FlvpInfoPage(),
                FlvpPageKey.settings => const FlvpSettingsPage(platform: FlvpPlatform.mobile),
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
                  bottom: (toast != null ? 166 : 100) + bottomInset,
                  child: _ExtendedFab(
                    collapsed: _scrollY > 24,
                    onTap: _openImport,
                  ),
                ),
              // MD3 navigation bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: navHeight,
                  padding: EdgeInsets.fromLTRB(8, 12, 8, bottomInset),
                  color: colors.frame,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in flvpNavItems)
                        _NavItem(
                          key: ValueKey('nav-${item.key.name}'),
                          icon: item.icon,
                          label: item.label,
                          active: _page == item.key,
                          onTap: () => _go(item.key),
                        ),
                    ],
                  ),
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
                  bottom: 100 + bottomInset,
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
      label: '导入订阅',
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
                      '导入订阅',
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

class _NavItem extends StatelessWidget {
  const _NavItem({
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
    return FlvpRipple(
      color: active ? colors.onscontainer : colors.ink,
      surface: const Rect.fromLTWH(6, 0, 64, 32),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          child: SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                SizedBox(
                  width: 64,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        duration: FlvpMotion.shape,
                        curve: FlvpMotion.easeEmph,
                        opacity: active ? 1 : 0,
                        child: AnimatedScale(
                          duration: FlvpMotion.shape,
                          curve: FlvpMotion.easeEmph,
                          scale: 1,
                          child: AnimatedContainer(
                            duration: FlvpMotion.shape,
                            curve: FlvpMotion.easeEmph,
                            width: active ? 64 : 64 * 0.4,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colors.scontainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      FlvpIcon(
                        icon,
                        size: 21,
                        strokeWidth: active ? 2.3 : 1.9,
                        color: active ? colors.onscontainer : colors.ink2,
                      ),
                    ],
                  ),
                ),
                Text(
                  label,
                  style: flvpText(
                    12,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? colors.ink : colors.ink2,
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
