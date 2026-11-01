import 'dart:async';
import 'dart:io';

import 'package:floway/common/common.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 关于：版本、来源链接与检查更新。上游的“其它贡献者”一栏已去掉。
class FlvpAboutPage extends ConsumerStatefulWidget {
  const FlvpAboutPage({super.key});

  @override
  ConsumerState<FlvpAboutPage> createState() => _FlvpAboutPageState();
}

class _FlvpAboutPageState extends ConsumerState<FlvpAboutPage> {
  bool _checking = false;
  int _logoTaps = 0;
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleLogoTap() {
    _logoTaps++;
    if (_logoTaps >= 5) {
      _logoTaps = 0;
      _tapTimer?.cancel();
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(developerMode: true));
      FlvpStoreScope.read(context).notify('已开启开发者选项');
      return;
    }
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(seconds: 1), () => _logoTaps = 0);
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final release = await request.checkForUpdate();
      if (!mounted) return;
      unawaited(
        ref
            .read(commonActionProvider.notifier)
            .checkUpdateResultHandle(data: release, isUser: true),
      );
    } catch (error) {
      if (mounted) {
        FlvpStoreScope.read(context).notify('检查更新失败：$error');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _open(String url) => unawaited(dialogs.openUrl(url));

  /// 包信息在启动流程里才写入；预览或测试里读不到时退回占位符。
  ({String version, String build})? get _packageInfo {
    try {
      final info = globalState.packageInfo;
      return (version: info.version, build: info.buildNumber);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final info = _packageInfo;
    final version = info == null ? '—' : 'v${info.version}';
    final platform = switch (Platform.operatingSystem) {
      'windows' => 'Windows',
      'android' => 'Android',
      _ => Platform.operatingSystem,
    };
    return FlvpPageScaffold(
      title: '关于',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _handleLogoTap,
                  child: Container(
                    width: 84,
                    height: 84,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xffffffff),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.hair),
                      boxShadow: FlvpElevation.card,
                    ),
                    child: Image.asset(
                      'assets/branding/floway.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  appName,
                  style: flvpText(22, letterSpacing: -0.4, color: colors.ink),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _Pill(
                      label: version,
                      color: colors.primary,
                      foreground: colors.onprimary,
                    ),
                    _Pill(
                      label: 'GPL-3.0',
                      color: colors.surf2,
                      foreground: colors.ink2,
                    ),
                    _Pill(
                      label: platform,
                      color: colors.surf2,
                      foreground: colors.ink2,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    currentAppLocalizations.desc,
                    textAlign: TextAlign.center,
                    style: flvpText(
                      12.5,
                      weight: FontWeight.w400,
                      height: 1.6,
                      color: colors.ink2,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FlvpButton(
                  variant: FlvpButtonVariant.tonal,
                  icon: FlvpSpin(
                    active: _checking,
                    child: const FlvpIcon('RefreshCw', size: 16),
                  ),
                  label: _checking ? '正在检查…' : '检查更新',
                  onPressed: _checking ? null : _checkUpdate,
                ),
              ],
            ),
          ),
          FlvpSettingsSection(
            title: '来源',
            children: [
              FlvpSettingsLink(
                icon: 'Globe',
                title: '项目',
                subtitle: 'github.com/$repository',
                onTap: () => _open('https://github.com/$repository'),
              ),
              FlvpSettingsLink(
                icon: 'Network',
                title: '内核',
                subtitle: 'github.com/chen08209/Clash.Meta',
                onTap: () => _open(
                  'https://github.com/chen08209/Clash.Meta/tree/FlClash',
                ),
              ),
              FlvpSettingsLink(
                icon: 'Info',
                title: '上游实现',
                subtitle: 'github.com/chen08209/FlClash',
                onTap: () => _open('https://github.com/chen08209/FlClash'),
              ),
            ],
          ),
          FlvpSettingsSection(
            title: '构建信息',
            children: [
              FlvpSettingsRow(
                icon: 'Archive',
                title: '版本',
                trailing: Text(
                  info == null ? '—' : '$version (${info.build})',
                  style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
                ),
              ),
              FlvpSettingsRow(
                icon: 'Server',
                title: '平台',
                trailing: Text(
                  platform,
                  style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
                ),
              ),
              FlvpSettingsRow(
                icon: 'Info',
                title: '许可证',
                trailing: Text(
                  'GPL-3.0',
                  style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: flvpText(12, weight: FontWeight.w600, color: foreground),
    ),
  );
}
