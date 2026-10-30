import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../nav.dart';
import '../store/design_store.dart';
import '../store/models.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/hero.dart';
import '../widgets/ripple.dart';
import '../widgets/surfaces.dart';

const List<FlvpSegmentedOption<FlvpProxyMode>> _modeOptions = [
  FlvpSegmentedOption(FlvpProxyMode.rule, '规则'),
  FlvpSegmentedOption(FlvpProxyMode.global, '全局'),
  FlvpSegmentedOption(FlvpProxyMode.direct, '直连'),
];

/// pages/Dashboard.tsx
class FlvpDashboardPage extends StatelessWidget {
  const FlvpDashboardPage({
    super.key,
    required this.platform,
    required this.onNavigate,
  });

  final FlvpPlatform platform;
  final ValueChanged<FlvpPageKey> onNavigate;

  @override
  Widget build(BuildContext context) => platform == FlvpPlatform.pc
      ? _DesktopDashboard(onNavigate: onNavigate)
      : _MobileDashboard(onNavigate: onNavigate);
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: flvpText(14, color: colors.ink, tabular: true),
        ),
      ],
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.label,
    required this.icon,
    required this.kb,
    required this.data,
    required this.tone,
    required this.scope,
    required this.total,
    this.compact = false,
  });

  final String label;
  final String icon;
  final double kb;
  final List<double> data;
  final FlvpSparklineTone tone;
  final String scope;
  final double total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final speed = fmtSpeed(kb);
    final primary = tone == FlvpSparklineTone.primary;
    return FlvpCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary
                      ? colors.pcontainer
                      : colors.ok.withValues(alpha: 0.15),
                ),
                child: FlvpIcon(
                  icon,
                  size: compact ? 14 : 15,
                  color: primary ? colors.onpcontainer : colors.ok,
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: flvpText(13, color: colors.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                speed.value,
                style: flvpText(
                  compact ? 24 : 30,
                  height: 1,
                  color: colors.ink,
                  tabular: true,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                speed.unit,
                style: flvpText(
                  12,
                  weight: FontWeight.w400,
                  color: colors.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FlvpSparkline(data: data, tone: tone, height: compact ? 32 : 40),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: '$scope ',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
              children: [
                TextSpan(
                  text: fmtGB(total),
                  style: flvpText(12, color: colors.ink2, tabular: true),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.onTap, required this.stretch});

  final VoidCallback onTap;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final sub = FlvpStoreScope.of(context).activeSub;
    final ratio = sub.total > 0 ? sub.used / sub.total : 0.0;
    if (!sub.hasQuota) {
      return FlvpCard(
        onTap: onTap,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 14,
          children: [
            Text('订阅流量', style: flvpText(13, color: colors.ink2)),
            Text('—', style: flvpText(32, color: colors.ink)),
            Text(
              sub.remote ? '未提供流量信息' : '本地配置 · 无订阅额度',
              style: flvpText(12, color: colors.ink3),
            ),
            Text(
              sub.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: flvpText(12, color: colors.ink2),
            ),
          ],
        ),
      );
    }
    final left = (sub.total - sub.used).clamp(0.0, double.infinity);
    return FlvpCard(
      padding: const EdgeInsets.all(20),
      onTap: onTap,
      hoverShadow: FlvpElevation.float,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text('订阅流量', style: flvpText(13, color: colors.ink2)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                sub.used.toStringAsFixed(1),
                style: flvpText(
                  30,
                  height: 1,
                  color: colors.ink,
                  tabular: true,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/ ${_trim(sub.total)} GB',
                style: flvpText(
                  12,
                  weight: FontWeight.w400,
                  color: colors.ink3,
                ),
              ),
            ],
          ),
          if (stretch) const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: FlvpProgressBar(
              value: ratio,
              tone: ratio > 0.75
                  ? FlvpProgressTone.warn
                  : FlvpProgressTone.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              text: '剩余 ',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
              children: [
                TextSpan(
                  text: '${left.toStringAsFixed(1)} GB',
                  style: flvpText(12, color: colors.ink2, tabular: true),
                ),
                TextSpan(text: ' · ${sub.name}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// `{activeSub.total}` renders 200, not 200.0.
String _trim(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({required this.onNavigate});

  final ValueChanged<FlvpPageKey> onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final scope = store.settings.statsScope == FlvpStatsScope.total
        ? '累计'
        : '本次';
    final node = store.currentNode;
    final running = store.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        FlvpCard(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlvpStatusPill(running: running),
                    const SizedBox(height: 16),
                    Text(
                      running ? '已连接' : '未连接',
                      style: flvpText(
                        34,
                        height: 1.25,
                        letterSpacing: -0.85,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      spacing: 8,
                      children: [
                        FlvpIcon('Globe2', size: 15, color: colors.ink3),
                        Text(
                          '${node.name} · ${node.proto}',
                          style: flvpText(
                            14,
                            weight: FontWeight.w400,
                            color: colors.ink2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Row(
                        spacing: 24,
                        children: [
                          Expanded(
                            child: _Meta(
                              label: '运行时长',
                              value: running
                                  ? fmtUptime(store.uptime)
                                  : '--:--:--',
                            ),
                          ),
                          Expanded(
                            child: _Meta(
                              label: '延迟',
                              value: running && node.latency != null
                                  ? '${node.latency} ms'
                                  : '—',
                            ),
                          ),
                          Expanded(
                            child: _Meta(
                              label: '订阅',
                              value: store.activeSub.name,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              FlvpPowerButton(
                running: running,
                onToggle: store.toggleRunning,
                size: 136,
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final download = _SpeedCard(
              label: '下载',
              icon: 'ArrowDown',
              kb: store.speed.down,
              data: store.hist['down']!,
              tone: FlvpSparklineTone.primary,
              scope: scope,
              total: store.traffic.down,
            );
            final upload = _SpeedCard(
              label: '上传',
              icon: 'ArrowUp',
              kb: store.speed.up,
              data: store.hist['up']!,
              tone: FlvpSparklineTone.ok,
              scope: scope,
              total: store.traffic.up,
            );
            // @2xl:grid-cols-3 — container query on the page content box.
            if (constraints.maxWidth >= 672) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Expanded(child: download),
                    Expanded(child: upload),
                    Expanded(
                      child: _QuotaCard(
                        onTap: () => onNavigate(FlvpPageKey.subs),
                        stretch: true,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      Expanded(child: download),
                      Expanded(child: upload),
                    ],
                  ),
                ),
                _QuotaCard(
                  onTap: () => onNavigate(FlvpPageKey.subs),
                  stretch: false,
                ),
              ],
            );
          },
        ),
        FlvpCard(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Text('代理模式', style: flvpText(13, color: colors.ink2)),
              const SizedBox(width: 16),
              FlvpSegmented<FlvpProxyMode>(
                size: FlvpControlSize.sm,
                value: store.settings.mode,
                onChanged: (mode) =>
                    store.setSettings((s) => s.copyWith(mode: mode)),
                options: _modeOptions,
              ),
              const Spacer(),
              FlvpHover(
                builder: (context, hovered) => FlvpRipple(
                  color: colors.ink,
                  borderRadius: BorderRadius.circular(999),
                  child: GestureDetector(
                    onTap: () => onNavigate(FlvpPageKey.nodes),
                    child: AnimatedContainer(
                      duration: FlvpMotion.hover,
                      height: 40,
                      padding: const EdgeInsets.only(left: 16, right: 12),
                      decoration: BoxDecoration(
                        color: hovered ? colors.surf3 : colors.surf2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          FlvpIcon('Route', size: 15, color: colors.ink3),
                          Text('节点', style: flvpText(13, color: colors.ink2)),
                          Text(
                            node.name,
                            style: flvpText(13, color: colors.ink),
                          ),
                          FlvpIcon(
                            'ChevronRight',
                            size: 16,
                            color: colors.ink3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({required this.onNavigate});

  final ValueChanged<FlvpPageKey> onNavigate;

  Widget _stat(FlvpColors colors, String icon, String value) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: colors.surf2,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      spacing: 6,
      children: [
        FlvpIcon(icon, size: 14, color: colors.ink2),
        Text(value, style: flvpText(12.5, color: colors.ink2, tabular: true)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final scope = store.settings.statsScope == FlvpStatsScope.total
        ? '累计'
        : '本次';
    final node = store.currentNode;
    final running = store.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        FlvpCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlvpPowerButton(
                running: running,
                onToggle: store.toggleRunning,
                size: 150,
              ),
              const SizedBox(height: 20),
              Text(
                running ? '已连接' : '未连接',
                style: flvpText(24, color: colors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                '${node.name} · ${node.proto}',
                style: flvpText(
                  13.5,
                  weight: FontWeight.w400,
                  color: colors.ink2,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  _stat(
                    colors,
                    'Timer',
                    running ? fmtUptime(store.uptime) : '--:--:--',
                  ),
                  _stat(
                    colors,
                    'Activity',
                    running && node.latency != null
                        ? '${node.latency} ms'
                        : '—',
                  ),
                ],
              ),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                child: _SpeedCard(
                  compact: true,
                  label: '下载',
                  icon: 'ArrowDown',
                  kb: store.speed.down,
                  data: store.hist['down']!,
                  tone: FlvpSparklineTone.primary,
                  scope: scope,
                  total: store.traffic.down,
                ),
              ),
              Expanded(
                child: _SpeedCard(
                  compact: true,
                  label: '上传',
                  icon: 'ArrowUp',
                  kb: store.speed.up,
                  data: store.hist['up']!,
                  tone: FlvpSparklineTone.ok,
                  scope: scope,
                  total: store.traffic.up,
                ),
              ),
            ],
          ),
        ),
        FlvpCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('代理模式', style: flvpText(13, color: colors.ink2)),
              ),
              FlvpSegmented<FlvpProxyMode>(
                full: true,
                value: store.settings.mode,
                onChanged: (mode) =>
                    store.setSettings((s) => s.copyWith(mode: mode)),
                options: _modeOptions,
              ),
            ],
          ),
        ),
        FlvpCard(
          padding: const EdgeInsets.all(16),
          onTap: () => onNavigate(FlvpPageKey.nodes),
          child: Row(
            spacing: 14,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.pcontainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: FlvpIcon('Route', size: 18, color: colors.onpcontainer),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('当前节点', style: flvpText(14.5, color: colors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      '${node.name} · ${node.sub}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: flvpText(
                        12.5,
                        weight: FontWeight.w400,
                        color: colors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              FlvpIcon('ChevronRight', size: 18, color: colors.ink3),
            ],
          ),
        ),
      ],
    );
  }
}
