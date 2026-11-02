import 'package:material_ui/material_ui.dart';

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
import '../widgets/outbound_card.dart';
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
          // 拼图里的窄格只有屏幕的 2/5，数字加单位可能放不下，按需等比缩小。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  speed.value,
                  style: flvpText(
                    compact ? 22 : 30,
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
  const _QuotaCard({
    required this.onTap,
    required this.stretch,
    this.showPercent = false,
  });

  final VoidCallback onTap;
  final bool stretch;

  /// 移动端拼图里把已用比例直接摆在标题行右侧。
  final bool showPercent;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  '订阅流量',
                  maxLines: 1,
                  style: flvpText(13, color: colors.ink2),
                ),
              ),
              if (showPercent)
                Text(
                  '${(ratio * 100).round()}%',
                  style: flvpText(
                    12,
                    weight: FontWeight.w600,
                    color: colors.ink3,
                    tabular: true,
                  ),
                ),
            ],
          ),
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
                        onTap: () => onNavigate(FlvpPageKey.profiles),
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
                  onTap: () => onNavigate(FlvpPageKey.profiles),
                  stretch: false,
                ),
              ],
            );
          },
        ),
        const FlvpOutboundCard(),
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
                    onTap: () => onNavigate(FlvpPageKey.proxies),
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

/// 节点行文案：`香港 01 · Hysteria2`，没选节点时退化成占位。
String _nodeLine(NodeInfo node) {
  final name = node.name.isEmpty ? '未选择节点' : node.name;
  return node.proto.isEmpty ? name : '$name · ${node.proto}';
}

/// 移动端仪表盘：一条横向启停状态条 + 拼图卡片（宽窄交替，按信息优先级排）。
class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({required this.onNavigate});

  final ValueChanged<FlvpPageKey> onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final scope = store.settings.statsScope == FlvpStatsScope.total
        ? '累计'
        : '本次';
    final node = store.currentNode;
    final running = store.running;
    // 拼图节奏：3/2 → 2/3 → 通栏 → 2/3，每行只有一张卡，行内等高由
    // IntrinsicHeight 兜住，字号放大也不会溢出。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _MobileStatusBar(
          running: running,
          node: node,
          uptime: store.uptime,
          onToggle: store.toggleRunning,
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                flex: 3,
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
                flex: 2,
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
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                flex: 2,
                child: _LatencyCard(running: running, latency: node.latency),
              ),
              Expanded(
                flex: 3,
                child: _QuotaCard(
                  onTap: () => onNavigate(FlvpPageKey.profiles),
                  stretch: false,
                  showPercent: true,
                ),
              ),
            ],
          ),
        ),
        const FlvpOutboundCard(),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                flex: 2,
                child: _ModeCard(
                  mode: store.settings.mode,
                  onChanged: (mode) =>
                      store.setSettings((s) => s.copyWith(mode: mode)),
                ),
              ),
              Expanded(
                flex: 3,
                child: _NodeCard(
                  node: node,
                  traffic: store.traffic,
                  onTap: () => onNavigate(FlvpPageKey.proxies),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 横向启停条：左电源键（连接时圆角方块 / 断开时圆形）、中状态与节点、
/// 右运行时长；整条可点，连接时整条铺主题色。
class _MobileStatusBar extends StatelessWidget {
  const _MobileStatusBar({
    required this.running,
    required this.node,
    required this.uptime,
    required this.onToggle,
  });

  final bool running;
  final NodeInfo node;
  final int uptime;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final strong = running ? colors.onprimary : colors.ink;
    final soft = running
        ? colors.onprimary.withValues(alpha: 0.78)
        : colors.ink2;
    final faint = running
        ? colors.onprimary.withValues(alpha: 0.66)
        : colors.ink3;
    return Semantics(
      button: true,
      label: running ? '停止代理' : '启动代理',
      child: FlvpRipple(
        color: running ? colors.onprimary : colors.ink,
        borderRadius: BorderRadius.circular(24),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: AnimatedContainer(
            duration: FlvpMotion.shape,
            curve: FlvpMotion.easeEmph,
            height: 76,
            padding: const EdgeInsets.fromLTRB(12, 0, 18, 0),
            decoration: BoxDecoration(
              color: running ? colors.primary : colors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: FlvpElevation.card,
            ),
            child: Row(
              spacing: 14,
              children: [
                AnimatedContainer(
                  duration: FlvpMotion.shape,
                  curve: FlvpMotion.easeEmph,
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: running
                        ? colors.onprimary.withValues(alpha: 0.20)
                        : colors.surf3,
                    borderRadius: BorderRadius.circular(running ? 16 : 999),
                  ),
                  child: FlvpIcon(
                    'Power',
                    size: 22,
                    strokeWidth: 2.2,
                    color: running ? colors.onprimary : colors.ink2,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        running ? '已连接' : '未连接',
                        maxLines: 1,
                        style: flvpText(
                          17,
                          weight: FontWeight.w600,
                          color: strong,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _nodeLine(node),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          12.5,
                          weight: FontWeight.w400,
                          color: soft,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '运行时长',
                      style: flvpText(
                        10.5,
                        weight: FontWeight.w400,
                        color: faint,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      running ? fmtUptime(uptime) : '--:--:--',
                      style: flvpText(
                        15,
                        weight: FontWeight.w600,
                        color: strong,
                        tabular: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拼图窄格：延迟与线路质量。
class _LatencyCard extends StatelessWidget {
  const _LatencyCard({required this.running, required this.latency});

  final bool running;
  final int? latency;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final raw = latency;
    final ms = running && raw != null && raw > 0 ? raw : null;
    final (String quality, Color tone) = ms == null
        ? (running ? '未测速' : '未连接', colors.ink3)
        : ms < 100
        ? ('线路优秀', colors.ok)
        : ms < 200
        ? ('线路一般', colors.warn)
        : ('线路较差', colors.err);
    return FlvpCard(
      padding: const EdgeInsets.all(16),
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
                  color: tone.withValues(alpha: 0.15),
                ),
                child: FlvpIcon('Gauge', size: 14, color: tone),
              ),
              const SizedBox(width: 10),
              Text('延迟', style: flvpText(13, color: colors.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  ms?.toString() ?? '—',
                  style: flvpText(
                    22,
                    height: 1,
                    color: colors.ink,
                    tabular: true,
                  ),
                ),
                if (ms != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    'ms',
                    style: flvpText(
                      12,
                      weight: FontWeight.w400,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Text(
            quality,
            style: flvpText(11.5, weight: FontWeight.w600, color: tone),
          ),
        ],
      ),
    );
  }
}

/// 拼图窄格：代理模式竖排。
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.onChanged});

  final FlvpProxyMode mode;
  final ValueChanged<FlvpProxyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text('代理模式', style: flvpText(13, color: colors.ink2)),
          for (final option in _modeOptions)
            _ModeSegment(
              label: option.label,
              selected: option.value == mode,
              onTap: () => onChanged(option.value),
            ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: selected ? colors.onprimary : colors.ink,
        borderRadius: BorderRadius.circular(selected ? 999 : 12),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: FlvpMotion.shape,
            curve: FlvpMotion.easeEmph,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary
                  : (hovered ? colors.surf3 : colors.surf2),
              borderRadius: BorderRadius.circular(selected ? 999 : 12),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: flvpText(
                12.5,
                color: selected ? colors.onprimary : colors.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 拼图宽格：当前节点 + 累计流量，点进代理页。
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.traffic,
    required this.onTap,
  });

  final NodeInfo node;
  final FlvpTraffic traffic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            spacing: 12,
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
                    Text(
                      '当前节点',
                      style: flvpText(11.5, color: colors.ink3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _nodeLine(node),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: flvpText(14, color: colors.ink),
                    ),
                  ],
                ),
              ),
              FlvpIcon('ChevronRight', size: 18, color: colors.ink3),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Text('累计流量', style: flvpText(11.5, color: colors.ink3)),
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: _TrafficStat(
                        icon: 'ArrowDown',
                        value: fmtGB(traffic.down),
                      ),
                    ),
                    Expanded(
                      child: _TrafficStat(
                        icon: 'ArrowUp',
                        value: fmtGB(traffic.up),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficStat extends StatelessWidget {
  const _TrafficStat({required this.icon, required this.value});

  final String icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Row(
      spacing: 6,
      children: [
        FlvpIcon(icon, size: 13, color: colors.ink3),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: flvpText(12.5, color: colors.ink, tabular: true),
          ),
        ),
      ],
    );
  }
}
