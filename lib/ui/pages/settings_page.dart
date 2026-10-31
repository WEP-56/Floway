import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/accents.dart';
import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../store/models.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/hero.dart';
import '../widgets/surfaces.dart';

enum _Panel { language, theme, backup, shortcuts, basic, advanced, close, stats, about }

/// pages/Settings.tsx
class FlvpSettingsPage extends StatefulWidget {
  const FlvpSettingsPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  State<FlvpSettingsPage> createState() => _FlvpSettingsPageState();
}

class _FlvpSettingsPageState extends State<FlvpSettingsPage> {
  final ValueNotifier<bool> _checking = ValueNotifier(false);
  Timer? _timer;

  bool get _pc => widget.platform == FlvpPlatform.pc;

  @override
  void dispose() {
    _timer?.cancel();
    _checking.dispose();
    super.dispose();
  }

  void _checkUpdate() {
    if (_checking.value) return;
    _checking.value = true;
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _checking.value = false;
      FlvpStoreScope.read(context).notify('已是最新版本 $flvpAppVersion');
    });
  }

  void _open(_Panel panel) {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => _SettingsPanel(
        panel: panel,
        platform: widget.platform,
        checking: _checking,
        onCheck: _checkUpdate,
        onClose: host.close,
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlvpSectionLabel(title: title),
        FlvpCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    ),
  );

  Widget _toggle({
    required String icon,
    required String title,
    required String summary,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => FlvpRow(
    icon: FlvpIcon(icon, size: 19),
    title: title,
    subtitle: summary,
    onTap: () => onChanged(!value),
    trailing: FlvpSwitch(value: value, onChanged: onChanged, label: title),
  );

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final s = store.settings;
    final pc = _pc;
    final closeLabel = pc
        ? (s.closeBehavior == FlvpCloseBehavior.tray ? '最小化到系统托盘' : '退出程序')
        : (s.closeBehavior == FlvpCloseBehavior.tray ? '保留后台运行' : '退出应用');

    // (group, estimated row count) — the row count drives the two-column
    // balancing that CSS `columns-2` + `break-inside-avoid` produces.
    final groups = <(Widget, int)>[
      (
        _group('通用', [
          FlvpRow(
            icon: const FlvpIcon('Languages', size: 19),
            title: '语言',
            subtitle: flvpLanguageLabels[s.language],
            onTap: () => _open(_Panel.language),
          ),
          FlvpRow(
            icon: const FlvpIcon('Palette', size: 19),
            title: '主题',
            subtitle: '${flvpThemeLabels[s.theme]} · ${flvpAccentSpecs[s.accent]!.label}',
            onTap: () => _open(_Panel.theme),
          ),
        ]),
        2,
      ),
      if (pc)
        (
          _group('快捷键', [
            FlvpRow(
              icon: const FlvpIcon('Keyboard', size: 19),
              title: '键盘快捷键',
              subtitle: '${flvpShortcuts.length} 个全局快捷键',
              onTap: () => _open(_Panel.shortcuts),
            ),
          ]),
          1,
        ),
      (
        _group('代理', [
          FlvpRow(
            icon: const FlvpIcon('Network', size: 19),
            title: '基本配置',
            subtitle: '混合端口 ${s.mixedPort} · 系统代理${s.systemProxy ? '已开启' : '已关闭'}',
            onTap: () => _open(_Panel.basic),
          ),
          FlvpRow(
            icon: const FlvpIcon('SlidersHorizontal', size: 19),
            title: '进阶配置',
            subtitle: '${s.tunMode ? 'TUN 模式' : '常规模式'} · ${flvpStacks[s.stack]} 网络栈',
            onTap: () => _open(_Panel.advanced),
          ),
        ]),
        2,
      ),
      (
        _group('应用行为', [
          _toggle(
            icon: 'Power',
            title: '开机自启动',
            summary: pc ? '登录系统后自动运行' : '设备开机后自动运行',
            value: s.autoStart,
            onChanged: (v) => store.setSettings((c) => c.copyWith(autoStart: v)),
          ),
          _toggle(
            icon: 'EyeOff',
            title: '静默启动',
            summary: pc ? '启动时不显示主窗口' : '启动时保持在后台',
            value: s.silentStart,
            onChanged: (v) => store.setSettings((c) => c.copyWith(silentStart: v)),
          ),
          _toggle(
            icon: 'Zap',
            title: '自动开启代理',
            summary: '应用启动后立即连接',
            value: s.autoConnect,
            onChanged: (v) => store.setSettings((c) => c.copyWith(autoConnect: v)),
          ),
          FlvpRow(
            icon: const FlvpIcon('LogOut', size: 19),
            title: pc ? '关闭按钮行为' : '返回键行为',
            subtitle: closeLabel,
            onTap: () => _open(_Panel.close),
          ),
          FlvpRow(
            icon: const FlvpIcon('BarChart3', size: 19),
            title: '统计范围',
            subtitle: s.statsScope == FlvpStatsScope.total ? '全部流量' : '本次会话',
            onTap: () => _open(_Panel.stats),
          ),
        ]),
        5,
      ),
      (
        _group('数据', [
          FlvpRow(
            icon: const FlvpIcon('Archive', size: 19),
            title: '备份与恢复',
            subtitle: '上次备份 10 月 8 日 21:34',
            onTap: () => _open(_Panel.backup),
          ),
        ]),
        1,
      ),
      (
        _group('关于', [
          FlvpRow(
            icon: const FlvpIcon('Info', size: 19),
            title: '版本信息',
            subtitle: '$flvpAppVersion · $flvpCoreVersion',
            onTap: () => _open(_Panel.about),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _checking,
            builder: (context, checking, _) => FlvpRow(
              icon: const FlvpIcon('RefreshCw', size: 19),
              title: '检查更新',
              subtitle: checking ? '正在检查…' : '当前已是最新版本',
              onTap: _checkUpdate,
              trailing: checking
                  ? const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: FlvpSpinner(size: 22),
                    )
                  : null,
            ),
          ),
        ]),
        2,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // `columns-1 gap-5 @2xl:columns-2`
        if (!pc || constraints.maxWidth < 672) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final (widget, _) in groups) widget],
          );
        }
        double height(int rows) => 29 + 12 + rows * 64 + 20;
        final total = groups.fold<double>(0, (sum, g) => sum + height(g.$2));
        var split = 1;
        var best = double.infinity;
        var running = 0.0;
        for (var i = 1; i < groups.length; i++) {
          running += height(groups[i - 1].$2);
          final candidate = math.max(running, total - running);
          if (candidate < best) {
            best = candidate;
            split = i;
          }
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final (widget, _) in groups.take(split)) widget],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final (widget, _) in groups.skip(split)) widget],
              ),
            ),
          ],
        );
      },
    );
  }
}

/* ------------------------------------------------------------------ */
/* Dialogs / bottom sheets                                             */
/* ------------------------------------------------------------------ */

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.panel,
    required this.platform,
    required this.checking,
    required this.onCheck,
    required this.onClose,
  });

  final _Panel panel;
  final FlvpPlatform platform;
  final ValueNotifier<bool> checking;
  final VoidCallback onCheck;
  final VoidCallback onClose;

  bool get pc => platform == FlvpPlatform.pc;

  /// Single-choice sheets on mobile dismiss themselves after picking.
  void _pick(void Function() apply) {
    apply();
    if (!pc) Timer(const Duration(milliseconds: 220), onClose);
  }

  Widget _label(FlvpColors colors, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(text, style: flvpText(13, weight: FontWeight.w600, color: colors.primary)),
  );

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final s = store.settings;
    FlvpModal modal({
      required String title,
      String? subtitle,
      Widget? icon,
      required Widget child,
    }) => FlvpModal(
      platform: platform,
      title: title,
      subtitle: subtitle,
      icon: icon,
      onClose: onClose,
      child: child,
    );

    return switch (panel) {
      _Panel.language => modal(
        title: '语言',
        subtitle: '选择界面显示语言',
        child: FlvpRadioList<FlvpLang>(
          value: s.language,
          onChanged: (v) => _pick(() => store.setSettings((c) => c.copyWith(language: v))),
          options: const [
            FlvpRadioOption(FlvpLang.zh, '简体中文'),
            FlvpRadioOption(FlvpLang.en, 'English'),
            FlvpRadioOption(FlvpLang.ja, '日本語'),
          ],
        ),
      ),
      _Panel.theme => modal(
        title: '主题',
        subtitle: '外观模式与动态配色',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24,
          children: [
            FlvpRadioList<FlvpThemeMode>(
              value: s.theme,
              onChanged: (v) => store.setSettings((c) => c.copyWith(theme: v)),
              options: [
                FlvpRadioOption(
                  FlvpThemeMode.system,
                  flvpThemeLabels[FlvpThemeMode.system]!,
                  description: '与系统外观保持一致',
                ),
                FlvpRadioOption(FlvpThemeMode.light, flvpThemeLabels[FlvpThemeMode.light]!),
                FlvpRadioOption(FlvpThemeMode.dark, flvpThemeLabels[FlvpThemeMode.dark]!),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(colors, '主题色'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final accent in FlvpAccent.values)
                        _AccentSwatch(
                          accent: accent,
                          selected: s.accent == accent,
                          onTap: () => store.setSettings((c) => c.copyWith(accent: accent)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _Panel.backup => modal(
        title: '备份与恢复',
        subtitle: '备份包含订阅、节点选择与全部设置',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            FlvpRow(
              background: colors.tile,
              hoverBackground: colors.tile,
              icon: const FlvpIcon('Upload', size: 18),
              title: '导出备份',
              subtitle: '保存为 .flvp 文件',
              onTap: () => store.notify('备份已导出'),
            ),
            FlvpRow(
              background: colors.tile,
              hoverBackground: colors.tile,
              icon: const FlvpIcon('Download', size: 18),
              title: '从文件恢复',
              subtitle: '选择备份文件并覆盖当前配置',
              onTap: () => store.notify('请选择备份文件'),
            ),
          ],
        ),
      ),
      _Panel.shortcuts => modal(
        title: '键盘快捷键',
        subtitle: '在系统任意位置均可使用',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            for (final shortcut in flvpShortcuts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.tile,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Text(shortcut.description, style: flvpText(14, color: colors.ink)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [for (final key in shortcut.keys) FlvpKbd(label: key)],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      _Panel.basic => modal(
        title: '基本配置',
        subtitle: '代理端口与系统接入方式',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Expanded(
                  child: FlvpField(
                    label: '混合端口',
                    value: s.mixedPort,
                    placeholder: '7890',
                    onChanged: (v) => store.setSettings((c) => c.copyWith(mixedPort: v)),
                  ),
                ),
                Expanded(
                  child: FlvpField(
                    label: 'SOCKS 端口',
                    value: s.socksPort,
                    placeholder: '7891',
                    onChanged: (v) => store.setSettings((c) => c.copyWith(socksPort: v)),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                FlvpTileToggle(
                  title: '系统代理',
                  summary: '自动设置系统 HTTP / SOCKS 代理',
                  value: s.systemProxy,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(systemProxy: v)),
                ),
                FlvpTileToggle(
                  title: '允许局域网连接',
                  summary: '局域网设备可通过本机代理上网',
                  value: s.allowLan,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(allowLan: v)),
                ),
                FlvpTileToggle(
                  title: 'TUN 模式',
                  summary: pc
                      ? '虚拟网卡接管全部流量；首次开启需在系统弹窗授权一次'
                      : '通过 VPN 接口接管全部流量',
                  value: s.tunMode,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(tunMode: v)),
                ),
                if (pc)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FlvpButton(
                      expand: true,
                      label: '卸载管理员协助进程',
                      onPressed: () => store.uninstallTunHelper(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      _Panel.advanced => modal(
        title: '进阶配置',
        subtitle: '内核高级选项，修改后自动重载',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                FlvpTileToggle(
                  title: '域名嗅探',
                  summary: '从 TLS / HTTP 流量中识别真实域名',
                  value: s.sniff,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(sniff: v)),
                ),
                FlvpTileToggle(
                  title: 'IPv6',
                  summary: '允许代理 IPv6 流量',
                  value: s.ipv6,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(ipv6: v)),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(colors, '日志级别'),
                FlvpSegmented<String>(
                  size: FlvpControlSize.sm,
                  full: true,
                  value: s.logLevel,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(logLevel: v)),
                  options: [
                    for (final level in flvpLogLevels)
                      FlvpSegmentedOption(level, level.toUpperCase()),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(colors, '网络栈'),
                FlvpRadioList<String>(
                  value: s.stack,
                  onChanged: (v) => store.setSettings((c) => c.copyWith(stack: v)),
                  options: [
                    for (final entry in flvpStacks.entries)
                      FlvpRadioOption(entry.key, entry.value),
                  ],
                ),
              ],
            ),
            FlvpField(
              label: 'DNS 服务器',
              value: s.dns,
              mono: true,
              onChanged: (v) => store.setSettings((c) => c.copyWith(dns: v)),
            ),
          ],
        ),
      ),
      _Panel.close => modal(
        title: pc ? '关闭按钮行为' : '返回键行为',
        subtitle: pc ? '点击窗口关闭按钮时' : '在主界面按下返回键时',
        child: FlvpRadioList<FlvpCloseBehavior>(
          value: s.closeBehavior,
          onChanged: (v) => _pick(() => store.setSettings((c) => c.copyWith(closeBehavior: v))),
          options: pc
              ? const [
                  FlvpRadioOption(
                    FlvpCloseBehavior.tray,
                    '最小化到系统托盘',
                    description: '窗口关闭后继续在后台运行',
                  ),
                  FlvpRadioOption(
                    FlvpCloseBehavior.quit,
                    '退出程序',
                    description: '关闭窗口并结束代理进程',
                  ),
                ]
              : const [
                  FlvpRadioOption(
                    FlvpCloseBehavior.tray,
                    '保留后台运行',
                    description: '返回桌面，代理保持连接',
                  ),
                  FlvpRadioOption(
                    FlvpCloseBehavior.quit,
                    '退出应用',
                    description: '结束应用并断开代理',
                  ),
                ],
        ),
      ),
      _Panel.stats => modal(
        title: '统计范围',
        subtitle: '仪表盘流量统计的计算方式',
        child: FlvpRadioList<FlvpStatsScope>(
          value: s.statsScope,
          onChanged: (v) => _pick(() => store.setSettings((c) => c.copyWith(statsScope: v))),
          options: const [
            FlvpRadioOption(FlvpStatsScope.total, '全部流量', description: '累计所有历史流量'),
            FlvpRadioOption(FlvpStatsScope.session, '本次会话', description: '仅统计本次启动后的流量'),
          ],
        ),
      ),
      _Panel.about => modal(
        icon: const FlvpAppMark(size: 64),
        title: 'FLVPcore',
        subtitle: '版本 $flvpAppVersion · $flvpBuildDate',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            FlvpRow(
              background: colors.tile,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: '内核',
              trailing: Text(
                flvpCoreVersion,
                style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
              ),
            ),
            FlvpRow(
              background: colors.tile,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: '平台',
              trailing: Text(
                pc ? 'Windows 11 · x64' : 'Android 15 · arm64',
                style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ValueListenableBuilder<bool>(
                valueListenable: checking,
                builder: (context, isChecking, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isChecking)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: FlvpWavyProgress(),
                      ),
                    FlvpButton(
                      expand: true,
                      onPressed: isChecking ? null : onCheck,
                      icon: FlvpSpin(
                        active: isChecking,
                        child: const FlvpIcon('RefreshCw', size: 16),
                      ),
                      label: isChecking ? '正在检查…' : '检查更新',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    };
  }
}

/// Android-style palette swatch button (theme dialog).
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final FlvpAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final swatch = flvpAccentSwatch(accent);
    return FlvpHover(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              AnimatedScale(
                duration: FlvpMotion.shape,
                curve: FlvpMotion.easeSpring,
                scale: selected ? 1 : (hovered ? 0.95 : 0.86),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      startAngle: math.pi,
                      endAngle: math.pi * 3,
                      colors: [
                        swatch.primary,
                        swatch.primary,
                        swatch.accent,
                        swatch.accent,
                        swatch.secondary,
                        swatch.secondary,
                      ],
                      stops: const [0, 0.5, 0.5, 0.75, 0.75, 1],
                    ),
                    boxShadow: selected ? FlvpElevation.card : null,
                  ),
                  child: selected
                      ? Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xe6ffffff),
                          ),
                          child: const FlvpIcon(
                            'Check',
                            size: 14,
                            strokeWidth: 3,
                            color: Color(0xff171717),
                          ),
                        )
                      : null,
                ),
              ),
              Text(
                flvpAccentSpecs[accent]!.label,
                style: flvpText(
                  12,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? colors.ink : colors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
