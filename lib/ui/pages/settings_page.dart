import 'dart:async';
import 'dart:math' as math;

import 'package:floway/common/app_localizations.dart';
import 'package:floway/common/constant.dart';
import 'package:floway/common/l10n_labels.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/views/access.dart';
import 'package:floway/views/backup_and_restore.dart';
import 'package:floway/views/config/dns.dart';
import 'package:floway/views/config/rules.dart';
import 'package:floway/views/config/scripts.dart';
import 'package:floway/views/config/user_agents.dart';
import 'package:floway/views/developer.dart';
import 'package:floway/views/font_family.dart';
import 'package:floway/views/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/theme_scope.dart';
import '../icons/flvp_icon.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/feedback.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/settings_section.dart';
import '../widgets/upstream_page.dart';
import 'settings/about_page.dart';
import 'settings/hotkey_page.dart';
import 'settings/inbound_page.dart';
import 'settings/custom_resources_page.dart';
import 'settings/network_page.dart';
import 'settings/on_demand_page.dart';

/// pages/Settings.tsx — 设置一级页。
///
/// 分组与排版沿用 Floway 卡片，内容全部来自上游：开关直接读写
/// `appSettingProvider` / `networkSettingProvider` / `patchClashConfigProvider`
/// （由上游 `configProvider` 监听后落盘），复杂项打开二级页。
class FlvpSettingsPage extends ConsumerStatefulWidget {
  const FlvpSettingsPage({
    super.key,
    required this.platform,
    this.onNavigate,
  });

  final FlvpPlatform platform;

  /// 移动端底栏只有四项，「信息」收进设置页，用这个回调跳过去。
  final ValueChanged<FlvpPageKey>? onNavigate;

  @override
  ConsumerState<FlvpSettingsPage> createState() => _FlvpSettingsPageState();
}

class _FlvpSettingsPageState extends ConsumerState<FlvpSettingsPage> {
  bool get _pc => widget.platform == FlvpPlatform.pc;

  void _open(Widget page) {
    unawaited(pushFlvpPage<void>(context, page));
  }

  /// 尚未改写成 Floway 版式的上游页面：套一层 Floway 配色再打开。
  void _openUpstream(Widget page) {
    unawaited(openFlvpUpstreamPage(context, page));
  }

  void _setApp(AppSettingProps Function(AppSettingProps state) update) {
    ref.read(appSettingProvider.notifier).update(update);
  }

  void _setClash(PatchClashConfig Function(PatchClashConfig state) update) {
    ref.read(patchClashConfigProvider.notifier).update(update);
  }

  void _setTheme(ThemeProps Function(ThemeProps state) update) {
    ref.read(themeSettingProvider.notifier).update(update);
  }

  /* ---------- dialogs ---------- */

  void _openLanguage() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '语言',
        subtitle: '界面与文案的显示语言',
        onClose: host.close,
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(
              appSettingProvider.select((state) => state.locale),
            );
            return FlvpRadioList<Locale?>(
              value: getLocaleForString(locale),
              options: const [
                FlvpRadioOption<Locale?>(null, '跟随系统'),
                FlvpRadioOption<Locale?>(
                  Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
                  '简体中文',
                ),
                FlvpRadioOption<Locale?>(
                  Locale.fromSubtags(languageCode: 'en'),
                  'English',
                ),
              ],
              onChanged: (value) {
                ref
                    .read(appSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(locale: value?.toString()),
                    );
                if (!_pc) host.close();
              },
            );
          },
        ),
      ),
    );
  }

  void _openTheme() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '主题',
        subtitle: '深浅模式、主题色与纯黑',
        onClose: host.close,
        child: Consumer(
          builder: (context, ref, _) {
            final theme = ref.watch(themeSettingProvider);
            final colors = FlvpThemeScope.colorsOf(context);
            final swatches = <int?>{
              null,
              ...defaultPrimaryColors,
            }.toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 20,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      '外观模式',
                      style: flvpText(13, color: colors.ink2),
                    ),
                    FlvpSegmented<ThemeMode>(
                      full: true,
                      value: theme.themeMode,
                      options: const [
                        FlvpSegmentedOption(ThemeMode.system, '跟随系统'),
                        FlvpSegmentedOption(ThemeMode.light, '浅色'),
                        FlvpSegmentedOption(ThemeMode.dark, '深色'),
                      ],
                      onChanged: (value) =>
                          _setTheme((state) => state.copyWith(themeMode: value)),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Text(
                      '主题色',
                      style: flvpText(13, color: colors.ink2),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final color in swatches)
                          _ThemeSwatch(
                            color: color == null ? null : Color(color),
                            selected: theme.primaryColor == color,
                            onTap: () => _setTheme(
                              (state) => state.copyWith(primaryColor: color),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      theme.primaryColor == null
                          ? '跟随系统取色'
                          : '自定义主题色',
                      style: flvpText(
                        12,
                        weight: FontWeight.w400,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ),
                FlvpTileToggle(
                  title: '纯黑模式',
                  summary: '深色下使用纯黑底，OLED 屏更省电',
                  value: theme.pureBlack,
                  onChanged: (value) =>
                      _setTheme((state) => state.copyWith(pureBlack: value)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openLogLevel() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '日志等级',
        subtitle: '内核产生日志的最低等级',
        onClose: host.close,
        child: Consumer(
          builder: (context, ref, _) {
            final level = ref.watch(
              patchClashConfigProvider.select((state) => state.logLevel),
            );
            return FlvpRadioList<LogLevel>(
              value: level,
              options: [
                for (final item in LogLevel.values)
                  FlvpRadioOption(item, item.name.toUpperCase()),
              ],
              onChanged: (value) {
                ref
                    .read(patchClashConfigProvider.notifier)
                    .update((state) => state.copyWith(logLevel: value));
                if (!_pc) host.close();
              },
            );
          },
        ),
      ),
    );
  }

  void _openDelayTimeout() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '测速超时',
        subtitle: '超过这个时间没有响应就记为超时',
        onClose: host.close,
        child: Consumer(
          builder: (context, ref, _) {
            final timeout = ref.watch(
              appSettingProvider.select((state) => state.delayTestTimeout),
            );
            return FlvpRadioList<int>(
              value: timeout,
              options: [
                for (final value in delayTestTimeoutOptions)
                  FlvpRadioOption(value, '$value ms'),
              ],
              onChanged: (value) {
                ref
                    .read(appSettingProvider.notifier)
                    .update((state) => state.copyWith(delayTestTimeout: value));
                if (!_pc) host.close();
              },
            );
          },
        ),
      ),
    );
  }

  void _openTabAnimation() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '页面切换动画',
        subtitle: '主页面之间的过渡方式',
        onClose: host.close,
        child: Consumer(
          builder: (context, ref, _) {
            final animation = ref.watch(
              appSettingProvider.select((state) => state.tabAnimation),
            );
            return FlvpRadioList<TabAnimation>(
              value: animation,
              options: const [
                FlvpRadioOption(TabAnimation.fade, '淡入淡出'),
                FlvpRadioOption(TabAnimation.slide, '左右滑动'),
              ],
              onChanged: (value) {
                ref
                    .read(appSettingProvider.notifier)
                    .update((state) => state.copyWith(tabAnimation: value));
                if (!_pc) host.close();
              },
            );
          },
        ),
      ),
    );
  }

  /* ---------- groups ---------- */

  List<(Widget, int)> _buildGroups() {
    final app = ref.watch(appSettingProvider);
    final clash = ref.watch(patchClashConfigProvider);
    final theme = ref.watch(themeSettingProvider);
    final pc = _pc;
    final localeLabel = app.locale == null
        ? '跟随系统'
        : (getLocaleForString(app.locale)?.label ?? app.locale!);
    final themeModeLabel = switch (theme.themeMode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
    final colorLabel = theme.primaryColor == null ? '动态取色' : '自定义配色';
    final fontLabel = theme.fontFamily ?? '系统默认';
    final scaleLabel = theme.textScale.enable
        ? ' · 字号 ${(theme.textScale.scale * 100).round()}%'
        : '';

    return [
      if (widget.onNavigate != null)
        (
          FlvpSettingsSection(
            title: '信息',
            children: [
              FlvpSettingsLink(
                icon: 'Activity',
                title: '连接与日志',
                subtitle: '连接、请求、DNS 与内核日志',
                onTap: () => widget.onNavigate!(FlvpPageKey.info),
              ),
            ],
          ),
          1,
        ),
      (
        FlvpSettingsSection(
          title: '外观与交互',
          children: [
            FlvpSettingsValue(
              icon: 'Languages',
              title: '语言',
              value: localeLabel,
              onTap: _openLanguage,
            ),
            FlvpSettingsValue(
              icon: 'Palette',
              title: '主题',
              value: '$themeModeLabel · $colorLabel',
              onTap: _openTheme,
            ),
            FlvpSettingsLink(
              icon: 'Settings',
              title: '字体与字号',
              subtitle: '$fontLabel$scaleLabel',
              onTap: () => _openUpstream(const FontFamilyView()),
            ),
            FlvpSettingsValue(
              icon: 'Zap',
              title: '页面切换动画',
              value: app.tabAnimation == TabAnimation.slide ? '左右滑动' : '淡入淡出',
              onTap: _openTabAnimation,
            ),
            if (!pc)
              FlvpSettingsToggle(
                icon: 'Square',
                title: '悬浮导航栏',
                subtitle: '滚动时导航栏浮在内容之上',
                value: app.floatingNavigationBar,
                onChanged: (value) => _setApp(
                  (state) => state.copyWith(floatingNavigationBar: value),
                ),
              ),
          ],
        ),
        5,
      ),
      (
        FlvpSettingsSection(
          title: '启动与后台',
          children: [
            if (pc)
              FlvpSettingsToggle(
                icon: 'Power',
                title: '开机自启动',
                subtitle: '登录系统后自动运行',
                value: app.autoLaunch,
                onChanged: (value) =>
                    _setApp((state) => state.copyWith(autoLaunch: value)),
              ),
            if (pc)
              FlvpSettingsToggle(
                icon: 'EyeOff',
                title: '静默启动',
                subtitle: '启动时不显示主窗口',
                value: app.silentLaunch,
                onChanged: (value) =>
                    _setApp((state) => state.copyWith(silentLaunch: value)),
              ),
            FlvpSettingsToggle(
              icon: 'Zap',
              title: '启动后自动连接',
              subtitle: '应用启动后自动开启代理',
              value: app.autoRun,
              onChanged: (value) =>
                  _setApp((state) => state.copyWith(autoRun: value)),
            ),
            if (pc)
              FlvpSettingsToggle(
                icon: 'LogOut',
                title: '退出时最小化',
                subtitle: '关闭窗口后留在托盘继续运行',
                value: app.minimizeOnExit,
                onChanged: (value) =>
                    _setApp((state) => state.copyWith(minimizeOnExit: value)),
              ),
            FlvpSettingsLink(
              icon: 'Timer',
              title: '按需连接',
              subtitle: '按 Wi-Fi 环境自动连接',
              onTap: () => _open(FlvpOnDemandPage(platform: widget.platform)),
            ),
            if (!pc)
              FlvpSettingsToggle(
                icon: 'EyeOff',
                title: '从任务列表隐藏',
                subtitle: '在最近任务中隐藏本应用',
                value: app.hidden,
                onChanged: (value) =>
                    _setApp((state) => state.copyWith(hidden: value)),
              ),
            if (!pc)
              FlvpSettingsToggle(
                icon: 'Info',
                title: '通知中的停止按钮',
                subtitle: '前台服务通知显示停止操作',
                value: app.showNotificationStopAction,
                onChanged: (value) => _setApp(
                  (state) => state.copyWith(showNotificationStopAction: value),
                ),
              ),
          ],
        ),
        pc ? 5 : 4,
      ),
      (
        FlvpSettingsSection(
          title: '代理与网络',
          children: [
            FlvpSettingsLink(
              icon: 'Server',
              title: '入站端口与认证',
              subtitle: '混合端口 ${clash.mixedPort} · 外部控制器'
                  '${clash.externalController == ExternalControllerStatus.open ? '已开启' : '已关闭'}',
              onTap: () => _open(FlvpInboundPage(platform: widget.platform)),
            ),
            FlvpSettingsLink(
              icon: 'Network',
              title: '网络设置',
              subtitle: '系统代理、TUN、排除域名与出站连接',
              onTap: () => _open(FlvpNetworkPage(platform: widget.platform)),
            ),
            FlvpSettingsValue(
              icon: 'Timer',
              title: '测速超时',
              value: '${app.delayTestTimeout} ms',
              onTap: _openDelayTimeout,
            ),
            FlvpSettingsToggle(
              icon: 'BarChart3',
              title: '仅统计代理流量',
              subtitle: '累计流量只计算经过代理的连接',
              value: app.onlyStatisticsProxy,
              onChanged: (value) => _setApp(
                (state) => state.copyWith(onlyStatisticsProxy: value),
              ),
            ),
            FlvpSettingsToggle(
              icon: 'X',
              title: '自动关闭连接',
              subtitle: '切换配置时关闭已有连接',
              value: app.closeConnections,
              onChanged: (value) =>
                  _setApp((state) => state.copyWith(closeConnections: value)),
            ),
            FlvpSettingsToggle(
              icon: 'Search',
              title: '按进程查找',
              subtitle: '连接列表显示发起请求的进程',
              value: clash.findProcessMode == FindProcessMode.always,
              onChanged: (value) => _setClash(
                (state) => state.copyWith(
                  findProcessMode: value
                      ? FindProcessMode.always
                      : FindProcessMode.off,
                ),
              ),
            ),
          ],
        ),
        6,
      ),
      (
        FlvpSettingsSection(
          title: '配置与规则',
          children: [
            FlvpSettingsLink(
              icon: 'Globe2',
              title: 'DNS',
              subtitle: '${clash.dns.enable ? '已启用' : '未启用'} · '
                  '${clash.dns.nameserver.length} 个上游',
              onTap: () => _openUpstream(const DnsView()),
            ),
            FlvpSettingsLink(
              icon: 'SlidersHorizontal',
              title: '附加规则',
              subtitle: '全局规则的顺序、匹配目标与选择器',
              onTap: () => _openUpstream(const AddedRulesView()),
            ),
            FlvpSettingsLink(
              icon: 'Activity',
              title: '脚本',
              subtitle: '本地与远程脚本、配置关联',
              onTap: () => _openUpstream(const ScriptsView()),
            ),
          ],
        ),
        3,
      ),
      (
        FlvpSettingsSection(
          title: '资源管理',
          children: [
            FlvpSettingsLink(
              icon: 'Archive',
              title: '自定义资源',
              subtitle: '代理资源、规则 Provider 与过滤器',
              onTap: () => _open(const FlvpCustomResourcesPage()),
            ),
            FlvpSettingsLink(
              icon: 'Download',
              title: '资源更新',
              subtitle: 'Geo 数据、远程规则、脚本与图标',
              onTap: () => _openUpstream(const ResourcesView()),
            ),
          ],
        ),
        2,
      ),
      (
        FlvpSettingsSection(
          title: '平台功能',
          children: [
            if (pc)
              FlvpSettingsLink(
                icon: 'Keyboard',
                title: '快捷键',
                subtitle: '全局快捷键的绑定与录制',
                onTap: () => _open(const FlvpHotKeyPage()),
              ),
            if (!pc)
              FlvpSettingsLink(
                icon: 'Settings',
                title: '应用访问控制',
                subtitle: '允许或拒绝指定应用走代理',
                onTap: () => _openUpstream(const AccessView()),
              ),
          ],
        ),
        1,
      ),
      (
        FlvpSettingsSection(
          title: '数据与备份',
          children: [
            FlvpSettingsLink(
              icon: 'Archive',
              title: '备份与恢复',
              subtitle: '本地文件与 WebDAV，含恢复策略',
              onTap: () => _openUpstream(const BackupAndRestore()),
            ),
          ],
        ),
        1,
      ),
      (
        FlvpSettingsSection(
          title: '应用与信息',
          children: [
            FlvpSettingsLink(
              icon: 'Globe2',
              title: '请求 User-Agent',
              subtitle: clash.globalUa ?? '默认',
              onTap: () => _openUpstream(const UserAgentsView()),
            ),
            FlvpSettingsToggle(
              icon: 'Check',
              title: '检查证书',
              subtitle: '订阅下载时校验服务器证书',
              value: app.checkCertificate,
              onChanged: (value) =>
                  _setApp((state) => state.copyWith(checkCertificate: value)),
            ),
            FlvpSettingsToggle(
              icon: 'RefreshCw',
              title: '自动检查更新',
              subtitle: '启动时检查新版本',
              value: app.autoCheckUpdate,
              onChanged: (value) =>
                  _setApp((state) => state.copyWith(autoCheckUpdate: value)),
            ),
            FlvpSettingsValue(
              icon: 'BarChart3',
              title: '日志等级',
              value: clash.logLevel.name.toUpperCase(),
              onTap: _openLogLevel,
            ),
            FlvpSettingsToggle(
              icon: 'Activity',
              title: '日志捕获',
              subtitle: '内核产生日志并在信息页展示',
              value: app.openLogs,
              onChanged: (value) =>
                  _setApp((state) => state.copyWith(openLogs: value)),
            ),
            FlvpSettingsLink(
              icon: 'Info',
              title: '关于',
              subtitle: '版本、内核与开源来源',
              onTap: () => _open(const FlvpAboutPage()),
            ),
            if (app.developerMode)
              FlvpSettingsLink(
                icon: 'Gauge',
                title: '开发者选项',
                subtitle: '诊断入口与实验性开关',
                onTap: () => _openUpstream(const DeveloperView()),
              ),
          ],
        ),
        app.developerMode ? 7 : 6,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups();
    return LayoutBuilder(
      builder: (context, constraints) {
        // `columns-1 gap-5 @2xl:columns-2`
        if (!_pc || constraints.maxWidth < 672) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final (widget, _) in groups) widget],
          );
        }
        double height(int rows) => 29 + 12 + rows * 64 + 20;
        final total = groups.fold<double>(
          0,
          (sum, group) => sum + height(group.$2),
        );
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
                children: [
                  for (final (widget, _) in groups.take(split)) widget,
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (widget, _) in groups.skip(split)) widget,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// `null` means the system's dynamic color.
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final fill = color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: fill ?? colors.surf2,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.ink : const Color(0x00000000),
            width: 2,
          ),
        ),
        child: fill == null
            ? Center(
                child: FlvpIcon('Sun', size: 18, color: colors.ink2),
              )
            : selected
            ? const Center(
                child: FlvpIcon(
                  'Check',
                  size: 18,
                  strokeWidth: 3,
                  color: Color(0xffffffff),
                ),
              )
            : null,
      ),
    );
  }
}
