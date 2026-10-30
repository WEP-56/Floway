import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../store/models.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';

/// pages/Subscriptions.tsx
class FlvpSubscriptionsPage extends StatelessWidget {
  const FlvpSubscriptionsPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final pc = platform == FlvpPlatform.pc;
    if (store.subs.isEmpty) {
      return FlvpCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FlvpIcon('Rss', size: 24, color: colors.ink2),
            ),
            Text('暂无订阅', style: flvpText(14.5, color: colors.ink)),
            Text(
              pc ? '点击右上角「导入订阅」添加' : '点击右下角按钮导入订阅',
              textAlign: TextAlign.center,
              style: flvpText(12.5, weight: FontWeight.w400, color: colors.ink3),
            ),
          ],
        ),
      );
    }
    final cards = [
      for (final sub in store.subs)
        _SubCard(key: ValueKey(sub.id), sub: sub, platform: platform),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // pc: gap-4 @3xl:grid-cols-2; mobile: single column, gap-3.
        if (!pc || constraints.maxWidth < 768) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: pc ? 16 : 12,
            children: cards,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            for (var i = 0; i < cards.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Expanded(child: cards[i]),
                    Expanded(
                      child: i + 1 < cards.length
                          ? cards[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

int _daysLeft(String expire) {
  final date = DateTime.tryParse(expire);
  if (date == null) return 1 << 30;
  return (date.difference(DateTime.now()).inMilliseconds / 86400000).ceil();
}

class _SubCard extends StatefulWidget {
  const _SubCard({super.key, required this.sub, required this.platform});

  final SubInfo sub;
  final FlvpPlatform platform;

  @override
  State<_SubCard> createState() => _SubCardState();
}

class _SubCardState extends State<_SubCard> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _menu;
  bool _updating = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _menu?.remove();
    _menu?.dispose();
    super.dispose();
  }

  void _update() {
    if (_updating) return;
    setState(() => _updating = true);
    _timer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      setState(() => _updating = false);
      FlvpStoreScope.read(context).refreshSub(widget.sub.id);
    });
  }

  void _closeMenu() {
    _menu?.remove();
    _menu?.dispose();
    _menu = null;
    if (mounted) setState(() {});
  }

  void _openMenu() {
    final theme = FlvpThemeScope.of(context);
    final store = FlvpStoreScope.read(context);
    final sub = widget.sub;
    final items = [
      (icon: 'Copy', label: '复制链接', danger: false, run: () => store.notify('订阅链接已复制')),
      (icon: 'Pencil', label: '编辑', danger: false, run: () => store.notify('编辑订阅暂未开放')),
      (icon: 'Trash2', label: '删除', danger: true, run: () => store.removeSub(sub.id)),
    ];
    _menu = OverlayEntry(
      builder: (context) => FlvpThemeScope(
        colors: theme.colors,
        accent: theme.accent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 4),
              child: _PopMenu(
                items: [
                  for (final item in items)
                    _PopMenuItem(
                      icon: item.icon,
                      label: item.label,
                      danger: item.danger,
                      onTap: () {
                        _closeMenu();
                        item.run();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_menu!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final sub = widget.sub;
    final mobile = widget.platform == FlvpPlatform.mobile;
    final ratio = sub.total > 0 ? sub.used / sub.total : 0.0;
    final left = (sub.total - sub.used).clamp(0.0, double.infinity);
    final low = ratio > 0.75;
    final daysLeft = _daysLeft(sub.expire);
    final expiring = daysLeft <= 30;
    final muted = sub.active ? colors.onpcontainer.withValues(alpha: 0.75) : colors.ink3;
    final metaStyle = flvpText(12, weight: FontWeight.w400, color: muted);

    return FlvpCard(
      padding: EdgeInsets.all(mobile ? 16 : 20),
      color: sub.active ? colors.pcontainer : colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: FlvpMotion.shape,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sub.active ? colors.primary : colors.surf2,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  sub.name.isEmpty ? '' : sub.name.substring(0, 1),
                  style: flvpText(
                    16,
                    weight: FontWeight.w600,
                    color: sub.active ? colors.onprimary : colors.ink2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              sub.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: flvpText(
                                15.5,
                                weight: FontWeight.w600,
                                color: sub.active ? colors.onpcontainer : colors.ink,
                              ),
                            ),
                          ),
                          if (sub.active) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '使用中',
                                style: flvpText(11, weight: FontWeight.w600, color: colors.onprimary),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(12.5, weight: FontWeight.w400, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(4, -4),
                child: CompositedTransformTarget(
                  link: _link,
                  child: FlvpIconButton(
                    label: '更多操作',
                    active: _menu != null,
                    onPressed: () => _menu != null ? _closeMenu() : _openMenu(),
                    icon: const FlvpIcon('MoreVertical', size: 19),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text.rich(
                TextSpan(
                  text: '已用 ',
                  style: flvpText(
                    12.5,
                    weight: FontWeight.w400,
                    color: sub.active ? colors.onpcontainer.withValues(alpha: 0.85) : colors.ink2,
                  ),
                  children: [
                    TextSpan(
                      text: sub.used.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    TextSpan(text: ' / ${_trim(sub.total)} GB'),
                  ],
                ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '剩余 ${left.toStringAsFixed(1)} GB',
                style: flvpText(
                  12.5,
                  weight: FontWeight.w600,
                  tabular: true,
                  color: low ? colors.warn : (sub.active ? colors.onpcontainer : colors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 10,
            child: Center(
              child: _updating
                  ? const FlvpWavyProgress()
                  : FlvpProgressBar(
                      value: ratio,
                      tone: low ? FlvpProgressTone.warn : FlvpProgressTone.primary,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        FlvpIcon(
                          expiring ? 'TriangleAlert' : 'CalendarClock',
                          size: 13,
                          color: expiring ? colors.warn : muted,
                        ),
                        Text(
                          expiring
                              ? (daysLeft > 0 ? '$daysLeft 天后到期' : '已到期')
                              : '到期 ${sub.expire}',
                          style: expiring
                              ? flvpText(12, color: colors.warn)
                              : metaStyle,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        FlvpIcon('RefreshCw', size: 13, color: muted),
                        Text(
                          _updating ? '正在更新…' : '${sub.updated}更新',
                          style: metaStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              FlvpIconButton(
                label: '更新订阅',
                onPressed: _update,
                icon: FlvpSpin(
                  active: _updating,
                  child: const FlvpIcon('RefreshCw', size: 18),
                ),
              ),
              if (!sub.active)
                FlvpButton(
                  size: FlvpControlSize.sm,
                  variant: FlvpButtonVariant.tonal,
                  label: '切换',
                  onPressed: () => store.activateSub(sub.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _trim(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

class _PopMenu extends StatefulWidget {
  const _PopMenu({required this.items});

  final List<Widget> items;

  @override
  State<_PopMenu> createState() => _PopMenuState();
}

class _PopMenuState extends State<_PopMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: FlvpMotion.pop,
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final pop = CurvedAnimation(parent: _enter, curve: FlvpMotion.easeEntrance);
    return FadeTransition(
      opacity: pop,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(pop),
        alignment: Alignment.topRight,
        child: Container(
          width: 176,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.dialog,
            borderRadius: BorderRadius.circular(16),
            boxShadow: FlvpElevation.float,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: widget.items),
        ),
      ),
    );
  }
}

class _PopMenuItem extends StatelessWidget {
  const _PopMenuItem({
    required this.icon,
    required this.label,
    required this.danger,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: FlvpMotion.hover,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: hovered ? colors.ink.withValues(alpha: 0.06) : const Color(0x00000000),
          child: Row(
            spacing: 12,
            children: [
              FlvpIcon(icon, size: 17, color: danger ? colors.err : colors.ink2),
              Text(
                label,
                style: flvpText(14, weight: FontWeight.w400, color: danger ? colors.err : colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
