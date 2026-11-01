import 'dart:async';
import 'dart:io';

import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../design/theme_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import 'string_list_page.dart';

/// 网络设置：系统代理、网络栈、出口网卡、TUN 与出站连接。
class FlvpNetworkPage extends ConsumerWidget {
  const FlvpNetworkPage({super.key, required this.platform});

  final FlvpPlatform platform;

  bool get _pc => platform == FlvpPlatform.pc;

  void _open(BuildContext context, Widget page) {
    unawaited(pushFlvpPage<void>(context, page));
  }

  Future<void> _editNumber(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int value,
    required int min,
    required int max,
    required PatchClashConfig Function(PatchClashConfig state, int value)
    apply,
  }) async {
    final next = await showFlvpNumberPrompt(
      context: context,
      platform: platform,
      title: title,
      value: value,
      min: min,
      max: max,
    );
    if (next == null || next == value) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => apply(state, next));
  }

  Future<void> _editStack(BuildContext context, WidgetRef ref) async {
    final clash = ref.read(patchClashConfigProvider);
    final next = await showFlvpOptionsPrompt<TunStack>(
      context: context,
      platform: platform,
      title: '网络栈',
      subtitle: 'TUN 使用的 TCP/IP 实现',
      value: clash.tun.stack,
      options: [
        for (final stack in TunStack.values)
          FlvpRadioOption(stack, stack.name),
      ],
    );
    if (next == null || next == clash.tun.stack) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(stack: next));
  }

  Future<void> _editInterfaceMode(BuildContext context, WidgetRef ref) async {
    final clash = ref.read(patchClashConfigProvider);
    final next = await showFlvpOptionsPrompt<InterfaceNameMode>(
      context: context,
      platform: platform,
      title: '出口网卡',
      subtitle: '出站流量绑定的网卡',
      value: clash.interfaceNameMode,
      options: const [
        FlvpRadioOption(InterfaceNameMode.clear, '不指定'),
        FlvpRadioOption(InterfaceNameMode.follow, '跟随系统默认'),
        FlvpRadioOption(InterfaceNameMode.custom, '手动指定'),
      ],
    );
    if (next == null || next == clash.interfaceNameMode) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(interfaceNameMode: next));
  }

  Future<void> _editInterfaceName(BuildContext context, WidgetRef ref) async {
    final clash = ref.read(patchClashConfigProvider);
    final next = await showFlvpTextPrompt(
      context: context,
      platform: platform,
      title: '网卡名称',
      subtitle: '例如 WLAN、以太网',
      value: clash.interfaceName,
      validator: (value) => value.isEmpty ? '请输入网卡名称' : null,
    );
    if (next == null || next == clash.interfaceName) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(interfaceName: next));
  }

  void _openLoopback() {
    final exe = p.join(p.dirname(Platform.resolvedExecutable), 'EnableLoopback.exe');
    windows?.runas('"$exe"', '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final clash = ref.watch(patchClashConfigProvider);
    final network = ref.watch(networkSettingProvider);
    final vpn = ref.watch(vpnSettingProvider);
    return FlvpPageScaffold(
      title: '网络设置',
      subtitle: _pc ? '系统代理、TUN 与出站连接' : 'VPN、绕过规则与出站连接',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pc)
            FlvpSettingsSection(
              title: '系统',
              footer: '排除域名里的地址不经过系统代理；回环代理需在系统里授权一次。',
              children: [
                FlvpSettingsToggle(
                  icon: 'Globe',
                  title: '系统代理',
                  subtitle: '自动设置系统 HTTP / SOCKS 代理',
                  value: network.systemProxy,
                  onChanged: (value) => ref
                      .read(networkSettingProvider.notifier)
                      .update((state) => state.copyWith(systemProxy: value)),
                ),
                FlvpSettingsLink(
                  icon: 'Route',
                  title: '排除域名',
                  subtitle: '${network.bypassDomain.length} 条',
                  onTap: () => _open(
                    context,
                    FlvpStringListPage(
                      platform: platform,
                      title: '排除域名',
                      subtitle: '这些域名不走系统代理',
                      values: network.bypassDomain,
                      placeholder: '例如 localhost',
                      footer: '每行一个域名或通配符，写入系统代理的绕过列表。',
                      onChanged: (values) => ref
                          .read(networkSettingProvider.notifier)
                          .update(
                            (state) => state.copyWith(bypassDomain: values),
                          ),
                    ),
                  ),
                ),
                if (system.isWindows)
                  FlvpSettingsLink(
                    icon: 'Server',
                    title: '回环代理',
                    subtitle: '允许 UWP 应用访问 127.0.0.1',
                    onTap: _openLoopback,
                  ),
              ],
            ),
          if (!_pc)
            FlvpSettingsSection(
              title: 'VPN',
              children: [
                FlvpSettingsToggle(
                  icon: 'Globe',
                  title: 'VPN 系统代理',
                  subtitle: '通过 VPN 接管系统代理设置',
                  value: vpn.systemProxy,
                  onChanged: (value) => ref
                      .read(vpnSettingProvider.notifier)
                      .update((state) => state.copyWith(systemProxy: value)),
                ),
                FlvpSettingsToggle(
                  icon: 'Route',
                  title: '允许绕过',
                  subtitle: '允许应用绕过 VPN 直接联网',
                  value: vpn.allowBypass,
                  onChanged: (value) => ref
                      .read(vpnSettingProvider.notifier)
                      .update((state) => state.copyWith(allowBypass: value)),
                ),
                FlvpSettingsToggle(
                  icon: 'Globe2',
                  title: 'IPv6',
                  subtitle: '在 VPN 内接管 IPv6 流量',
                  value: vpn.ipv6,
                  onChanged: (value) => ref
                      .read(vpnSettingProvider.notifier)
                      .update((state) => state.copyWith(ipv6: value)),
                ),
                FlvpSettingsToggle(
                  icon: 'Search',
                  title: 'DNS 劫持',
                  subtitle: '把 VPN 内的 DNS 请求交给内核处理',
                  value: vpn.dnsHijacking,
                  onChanged: (value) => ref
                      .read(vpnSettingProvider.notifier)
                      .update((state) => state.copyWith(dnsHijacking: value)),
                ),
                FlvpSettingsLink(
                  icon: 'Route',
                  title: '排除域名',
                  subtitle: '${network.bypassDomain.length} 条',
                  onTap: () => _open(
                    context,
                    FlvpStringListPage(
                      platform: platform,
                      title: '排除域名',
                      subtitle: '这些域名不经过 VPN',
                      values: network.bypassDomain,
                      placeholder: '例如 localhost',
                      onChanged: (values) => ref
                          .read(networkSettingProvider.notifier)
                          .update(
                            (state) => state.copyWith(bypassDomain: values),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          if (_pc)
            FlvpSettingsSection(
              title: 'TUN 接管',
              footer: 'TUN 只在桌面端使用；安卓走 VPN 接管，没有这一层。',
              children: [
                FlvpSettingsToggle(
                  icon: 'Network',
                  title: 'TUN 模式',
                  subtitle: '虚拟网卡接管全部流量',
                  value: clash.tun.enable,
                  onChanged: (value) => ref
                      .read(patchClashConfigProvider.notifier)
                      .update((state) => state.copyWith.tun(enable: value)),
                ),
                FlvpSettingsValue(
                  icon: 'Activity',
                  title: '网络栈',
                  value: clash.tun.stack.name,
                  onTap: () => _editStack(context, ref),
                ),
                FlvpSettingsValue(
                  icon: 'Server',
                  title: '出口网卡',
                  value: switch (clash.interfaceNameMode) {
                    InterfaceNameMode.clear => '不指定',
                    InterfaceNameMode.follow => '跟随系统',
                    InterfaceNameMode.custom => '手动指定',
                  },
                  onTap: () => _editInterfaceMode(context, ref),
                ),
                if (clash.interfaceNameMode == InterfaceNameMode.custom)
                  FlvpSettingsValue(
                    icon: 'Network',
                    title: '网卡名称',
                    value: clash.interfaceName.isEmpty ? '未设置' : clash.interfaceName,
                    onTap: () => _editInterfaceName(context, ref),
                  ),
              ],
            ),
          if (_pc)
            FlvpSettingsSection(
              title: 'TUN 路由',
              footer: '路由地址与排除地址按 CIDR 填写；绕过私有网段可避免接管局域网访问。',
              children: [
              FlvpSettingsValue(
                icon: 'Gauge',
                title: 'MTU',
                value: '${clash.tun.mtu}',
                onTap: () => _editNumber(
                  context,
                  ref,
                  title: 'MTU',
                  value: clash.tun.mtu,
                  min: minTunMtu,
                  max: maxTunMtu,
                  apply: (state, value) => state.copyWith.tun(mtu: value),
                ),
              ),
              FlvpSettingsLink(
                icon: 'Route',
                title: '路由地址',
                subtitle: '${clash.tun.routeAddress.length} 条',
                onTap: () => _open(
                  context,
                  FlvpStringListPage(
                    platform: platform,
                    title: '路由地址',
                    subtitle: 'TUN 网卡自身的地址段',
                    values: clash.tun.routeAddress,
                    placeholder: '198.18.0.1/16',
                    footer: '按 CIDR 填写，留空表示由内核决定。',
                    onChanged: (values) => ref
                        .read(patchClashConfigProvider.notifier)
                        .update(
                          (state) => state.copyWith.tun(routeAddress: values),
                        ),
                  ),
                ),
              ),
              FlvpSettingsLink(
                icon: 'Route',
                title: '路由排除地址',
                subtitle: '${clash.tun.routeExcludeAddress.length} 条',
                onTap: () => _open(
                  context,
                  FlvpStringListPage(
                    platform: platform,
                    title: '路由排除地址',
                    subtitle: '这些地址段不进入 TUN',
                    values: clash.tun.routeExcludeAddress,
                    placeholder: '例如 192.168.0.0/16',
                    onChanged: (values) => ref
                        .read(patchClashConfigProvider.notifier)
                        .update(
                          (state) => state.copyWith
                              .tun(routeExcludeAddress: values),
                        ),
                  ),
                ),
              ),
              FlvpSettingsToggle(
                icon: 'Route',
                title: '绕过私有网段',
                subtitle: '私有地址不进入 TUN',
                value: network.bypassPrivateRoute,
                onChanged: (value) => ref
                    .read(networkSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(bypassPrivateRoute: value),
                    ),
              ),
            ],
          ),
          FlvpSettingsSection(
            title: '出站连接',
            footer: 'Keep-Alive 只影响直连与代理链的 TCP 连接复用。',
            children: [
              FlvpSettingsToggle(
                icon: 'Zap',
                title: '禁用 Keep-Alive',
                subtitle: '每条连接用完即关闭',
                value: clash.disableKeepAlive,
                onChanged: (value) => ref
                    .read(patchClashConfigProvider.notifier)
                    .update(
                      (state) => state.copyWith(disableKeepAlive: value),
                    ),
              ),
              FlvpSettingsValue(
                icon: 'Timer',
                title: 'Keep-Alive 空闲',
                value: '${clash.keepAliveIdle} 秒',
                onTap: () => _editNumber(
                  context,
                  ref,
                  title: 'Keep-Alive 空闲',
                  value: clash.keepAliveIdle,
                  min: 0,
                  max: 3600,
                  apply: (state, value) =>
                      state.copyWith(keepAliveIdle: value),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Timer',
                title: 'Keep-Alive 间隔',
                value: '${clash.keepAliveInterval} 秒',
                onTap: () => _editNumber(
                  context,
                  ref,
                  title: 'Keep-Alive 间隔',
                  value: clash.keepAliveInterval,
                  min: 0,
                  max: 3600,
                  apply: (state, value) =>
                      state.copyWith(keepAliveInterval: value),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _pc
                  ? '网络相关的改动会在应用配置后生效；切换 TUN 时系统可能再确认一次网络接管。'
                  : '网络相关的改动会在应用配置后生效；VPN 权限或绕过规则变化时，系统可能再确认一次网络接管。',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
