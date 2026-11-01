import 'dart:async';

import 'package:floway/common/common.dart';
import 'package:floway/plugins/app.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 按需连接：前置权限与「排除的 SSID」列表。
class FlvpOnDemandPage extends ConsumerWidget {
  const FlvpOnDemandPage({super.key, required this.platform});

  final FlvpPlatform platform;

  bool get _needsLocationPermission =>
      system.isAndroid || system.isWindows || system.isMacOS;

  Future<void> _requestLocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final permission = ref.read(locationPermissionsProvider);
    if (permission == WifiSsidPermission.granted) return;
    if (permission == WifiSsidPermission.permanentlyDenied) {
      await _explainDenied(context);
      return;
    }
    final WifiSsidPermission? result;
    try {
      result = await ref.read(locationPermissionsProvider.notifier).request();
    } on PlatformException catch (error) {
      commonPrint.log('requestPermission error $error');
      return;
    }
    if (result == WifiSsidPermission.denied && context.mounted) {
      await _explainDenied(context);
    }
  }

  Future<void> _explainDenied(BuildContext context) async {
    final appLocalizations = currentAppLocalizations;
    final go = await dialogs.showMessage(
      title: appLocalizations.locationPermissionRequired,
      message: TextSpan(
        text: system.isAndroid
            ? appLocalizations.locationPermissionGuide(appName)
            : appLocalizations.locationPermissionDeniedMessage,
      ),
      confirmText: appLocalizations.go,
    );
    if (go != true) return;
    if (system.isWindows) {
      unawaited(launchUrl(Uri.parse('ms-settings:privacy-location')));
    } else {
      unawaited(app?.openAppSettings());
    }
  }

  Future<void> _addOrEditSsid(
    BuildContext context,
    WidgetRef ref, {
    String? ssid,
  }) async {
    final ssids = ref.read(excludeSSIDsProvider);
    final next = await showFlvpTextPrompt(
      context: context,
      platform: platform,
      title: ssid == null ? '添加 SSID' : '编辑 SSID',
      subtitle: '连接到这些 Wi-Fi 时不自动开启代理',
      value: ssid ?? '',
      placeholder: 'Wi-Fi 名称',
      validator: (value) {
        if (value.isEmpty) return '请输入 SSID';
        if (value != ssid && ssids.contains(value)) return '这个 SSID 已经在列表里';
        return null;
      },
    );
    if (next == null || next == ssid) return;
    ref.read(excludeSSIDsProvider.notifier).update((state) {
      final result = state.toSet();
      if (ssid != null) result.remove(ssid);
      return [...result, next];
    });
  }

  void _remove(WidgetRef ref, String ssid) {
    ref
        .read(excludeSSIDsProvider.notifier)
        .update((state) => state.where((item) => item != ssid).toList());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final ssids = ref.watch(excludeSSIDsProvider);
    final granted = ref.watch(
      locationPermissionsProvider.select(
        (state) => state == WifiSsidPermission.granted,
      ),
    );
    final batteryIgnored = ref.watch(batteryOptimizationIgnoredProvider);
    return FlvpPageScaffold(
      title: '按需连接',
      subtitle: '按 Wi-Fi 环境决定是否自动连接',
      actions: [
        FlvpIconButton(
          label: '添加 SSID',
          dimension: 40,
          onPressed: () => _addOrEditSsid(context, ref),
          icon: const FlvpIcon('Plus', size: 19),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '前提条件',
            footer: '按需连接需要读取当前 Wi-Fi 名称，部分平台还要求定位权限。',
            children: [
              if (system.isAndroid)
                FlvpSettingsRow(
                  icon: 'Zap',
                  title: '忽略电池优化',
                  subtitle: '避免后台被系统回收',
                  trailing: FlvpButton(
                    size: FlvpControlSize.sm,
                    variant: batteryIgnored.value == true
                        ? FlvpButtonVariant.text
                        : FlvpButtonVariant.tonal,
                    label: batteryIgnored.value == true ? '已允许' : '去允许',
                    onPressed: batteryIgnored.value == true
                        ? null
                        : () => ref
                              .read(batteryOptimizationIgnoredProvider.notifier)
                              .request(),
                  ),
                ),
              if (_needsLocationPermission)
                FlvpSettingsRow(
                  icon: 'Search',
                  title: '位置权限',
                  subtitle: '读取 Wi-Fi 名称所需的系统权限',
                  trailing: FlvpButton(
                    size: FlvpControlSize.sm,
                    variant: granted
                        ? FlvpButtonVariant.text
                        : FlvpButtonVariant.tonal,
                    label: granted ? '已授权' : '去授权',
                    onPressed: granted
                        ? null
                        : () => _requestLocation(context, ref),
                  ),
                ),
            ],
          ),
          FlvpSettingsSection(
            title: '排除的 SSID',
            footer: ssids.isEmpty
                ? '列表为空时，任何 Wi-Fi 下都按「启动后自动连接」处理。'
                : '共 ${ssids.length} 个 Wi-Fi 不自动连接。',
            children: [
              if (ssids.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 28,
                  ),
                  child: Column(
                    spacing: 10,
                    children: [
                      FlvpIcon('Network', size: 24, color: colors.ink3),
                      Text(
                        '还没有排除任何 Wi-Fi',
                        style: flvpText(13, color: colors.ink3),
                      ),
                    ],
                  ),
                )
              else
                for (final ssid in ssids)
                  FlvpSettingsRow(
                    icon: 'Network',
                    title: ssid,
                    onTap: () => _addOrEditSsid(context, ref, ssid: ssid),
                    trailing: FlvpIconButton(
                      label: '删除 $ssid',
                      dimension: 32,
                      onPressed: () => _remove(ref, ssid),
                      icon: FlvpIcon('X', size: 14, color: colors.ink3),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
