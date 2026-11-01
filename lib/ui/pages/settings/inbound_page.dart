import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../store/store_scope.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 入站端口与认证：混合/HTTP/SOCKS/redir/TProxy 端口、外部控制器、代理认证。
///
/// 与「启动与后台」不重复：局域网开关放在这里，开机/后台行为在那边。
class FlvpInboundPage extends ConsumerWidget {
  const FlvpInboundPage({super.key, required this.platform});

  final FlvpPlatform platform;

  static const _minPort = 1024;
  static const _maxPort = 49151;

  Future<void> _editPort(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int value,
    required bool required,
    required PatchClashConfig Function(PatchClashConfig state, int value) apply,
  }) async {
    final next = await showFlvpNumberPrompt(
      context: context,
      platform: platform,
      title: title,
      subtitle: required ? '必填，监听在本机的代理端口' : '设为 0 表示不监听这个端口',
      value: value,
      min: required ? _minPort : 0,
      max: _maxPort,
    );
    if (next == null || next == value) return;
    if (!context.mounted) return;
    final clash = ref.read(patchClashConfigProvider);
    final others = [
      clash.mixedPort,
      clash.port,
      clash.socksPort,
      clash.redirPort,
      clash.tproxyPort,
    ]..remove(value);
    if (next != 0 && others.contains(next)) {
      FlvpStoreScope.read(context).notify('端口 $next 已被其它入站端口占用');
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => apply(state, next));
  }

  Future<void> _editText(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String value,
    required String? Function(String value) validator,
    required PatchClashConfig Function(PatchClashConfig state, String value)
    apply,
  }) async {
    final next = await showFlvpTextPrompt(
      context: context,
      platform: platform,
      title: title,
      value: value,
      validator: validator,
    );
    if (next == null || next == value) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => apply(state, next));
  }

  Future<void> _editNetworkText(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String value,
    required String? Function(String value) validator,
    required NetworkProps Function(NetworkProps state, String value) apply,
  }) async {
    final next = await showFlvpTextPrompt(
      context: context,
      platform: platform,
      title: title,
      value: value,
      validator: validator,
    );
    if (next == null || next == value) return;
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => apply(state, next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final clash = ref.watch(patchClashConfigProvider);
    final network = ref.watch(networkSettingProvider);
    final controllerOpen =
        clash.externalController == ExternalControllerStatus.open;
    return FlvpPageScaffold(
      title: '入站端口与认证',
      subtitle: '本机代理监听的端口与访问控制',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '入站端口',
            footer: '端口范围 $_minPort – $_maxPort；除混合端口外，设为 0 表示关闭该入站。',
            children: [
              FlvpSettingsValue(
                icon: 'Server',
                title: '混合端口',
                value: '${clash.mixedPort}',
                onTap: () => _editPort(
                  context,
                  ref,
                  title: '混合端口',
                  value: clash.mixedPort,
                  required: true,
                  apply: (state, value) => state.copyWith(mixedPort: value),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Globe',
                title: 'HTTP 端口',
                value: clash.port == 0 ? '未启用' : '${clash.port}',
                onTap: () => _editPort(
                  context,
                  ref,
                  title: 'HTTP 端口',
                  value: clash.port,
                  required: false,
                  apply: (state, value) => state.copyWith(port: value),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Route',
                title: 'SOCKS 端口',
                value: clash.socksPort == 0 ? '未启用' : '${clash.socksPort}',
                onTap: () => _editPort(
                  context,
                  ref,
                  title: 'SOCKS 端口',
                  value: clash.socksPort,
                  required: false,
                  apply: (state, value) => state.copyWith(socksPort: value),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Network',
                title: 'Redir 端口',
                value: clash.redirPort == 0 ? '未启用' : '${clash.redirPort}',
                onTap: () => _editPort(
                  context,
                  ref,
                  title: 'Redir 端口',
                  value: clash.redirPort,
                  required: false,
                  apply: (state, value) => state.copyWith(redirPort: value),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Zap',
                title: 'TProxy 端口',
                value: clash.tproxyPort == 0 ? '未启用' : '${clash.tproxyPort}',
                onTap: () => _editPort(
                  context,
                  ref,
                  title: 'TProxy 端口',
                  value: clash.tproxyPort,
                  required: false,
                  apply: (state, value) => state.copyWith(tproxyPort: value),
                ),
              ),
            ],
          ),
          FlvpSettingsSection(
            title: '访问控制',
            footer: '局域网开放后，同一网络内的设备可以把本机当作代理。',
            children: [
              FlvpSettingsToggle(
                icon: 'Server',
                title: '允许局域网连接',
                subtitle: '局域网设备可通过本机代理上网',
                value: clash.allowLan,
                onChanged: (value) => ref
                    .read(patchClashConfigProvider.notifier)
                    .update((state) => state.copyWith(allowLan: value)),
              ),
              FlvpSettingsToggle(
                icon: 'Settings',
                title: '外部控制器',
                subtitle: '通过 HTTP API 控制内核（本机 9090）',
                value: controllerOpen,
                onChanged: (value) => ref
                    .read(patchClashConfigProvider.notifier)
                    .update(
                      (state) => state
                          .copyWith(
                            externalController: value
                                ? ExternalControllerStatus.open
                                : ExternalControllerStatus.close,
                          )
                          .ensureControllerSecret(),
                    ),
              ),
              if (controllerOpen)
                FlvpSettingsValue(
                  icon: 'Keyboard',
                  title: '控制器密钥',
                  value: clash.secret.isEmpty ? '未设置' : '已设置',
                  onTap: () => _editText(
                    context,
                    ref,
                    title: '控制器密钥',
                    value: clash.secret,
                    validator: (value) => value.isEmpty ? '密钥不能为空' : null,
                    apply: (state, value) => state.copyWith(secret: value),
                  ),
                ),
              FlvpSettingsToggle(
                icon: 'LogOut',
                title: '代理认证',
                subtitle: '访问本机代理需要用户名与密码',
                value: network.authentication.enable,
                onChanged: (value) => ref
                    .read(networkSettingProvider.notifier)
                    .update((state) {
                      var authentication = state.authentication.copyWith(
                        enable: value,
                      );
                      if (value && authentication.username.isEmpty) {
                        authentication = authentication.copyWith(
                          username: generateRandomSecret(8),
                          password: generateRandomSecret(16),
                        );
                      }
                      return state.copyWith(authentication: authentication);
                    }),
              ),
              if (network.authentication.enable) ...[
                FlvpSettingsValue(
                  icon: 'Info',
                  title: '账号',
                  value: network.authentication.username,
                  onTap: () => _editNetworkText(
                    context,
                    ref,
                    title: '账号',
                    value: network.authentication.username,
                    validator: (value) => value.isEmpty ? '账号不能为空' : null,
                    apply: (state, value) => state.copyWith.authentication(
                      username: value.replaceAll(':', ''),
                    ),
                  ),
                ),
                FlvpSettingsValue(
                  icon: 'Keyboard',
                  title: '密码',
                  value: network.authentication.password.isEmpty
                      ? '未设置'
                      : '••••••',
                  onTap: () => _editNetworkText(
                    context,
                    ref,
                    title: '密码',
                    value: network.authentication.password,
                    validator: (value) => value.isEmpty ? '密码不能为空' : null,
                    apply: (state, value) =>
                        state.copyWith.authentication(password: value),
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '修改端口与认证后，内核会按新的入站配置重启监听；正在使用旧端口的应用需要重新连接。',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
