import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store/design_store.dart';
import 'store/models.dart';

Mode _toMode(FlvpProxyMode mode) => switch (mode) {
  FlvpProxyMode.rule => Mode.rule,
  FlvpProxyMode.global => Mode.global,
  FlvpProxyMode.direct => Mode.direct,
};

FlvpProxyMode _toFlvpMode(Mode mode) => switch (mode) {
  Mode.rule => FlvpProxyMode.rule,
  Mode.global => FlvpProxyMode.global,
  Mode.direct => FlvpProxyMode.direct,
};

const double _bytesPerGb = 1024 * 1024 * 1024.0;

String _two(int value) => value.toString().padLeft(2, '0');

String _dateText(DateTime? value) => value == null
    ? '—'
    : '${value.year}-${_two(value.month)}-${_two(value.day)}';

String _stampText(DateTime? value) => value == null
    ? '—'
    : '${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';

/// 上游配置到界面的映射：用量、到期与更新时间取上游已有的订阅信息，
/// 没有时保持界面已有的缺省呈现。
SubInfo _toSubInfo(Profile profile, int? currentProfileId) {
  final info = profile.subscriptionInfo;
  return SubInfo(
    id: profile.id.toString(),
    name: profile.label.isEmpty ? '未命名配置' : profile.label,
    url: profile.url,
    used: info == null ? 0 : (info.upload + info.download) / _bytesPerGb,
    total: info == null ? 0 : info.total / _bytesPerGb,
    expire: _dateText(info?.expireDate),
    updated: _stampText(profile.lastUpdateDate),
    active: profile.id == currentProfileId,
    remote: profile.type == ProfileType.url,
    hasQuota: info != null,
  );
}

List<SubInfo> _toSubInfos(List<Profile> profiles, int? currentProfileId) => [
  for (final profile in profiles) _toSubInfo(profile, currentProfileId),
];

/// 把 Floway 壳接到上游状态与动作上：上游是唯一真相，变化后由
/// [ref.listenManual] 回推给设计 store，避免界面状态与内核实态分叉。
class FlvpBackendBinder extends ConsumerStatefulWidget {
  const FlvpBackendBinder({
    super.key,
    required this.store,
    required this.child,
  });

  final FlvpDesignStore store;
  final Widget child;

  @override
  ConsumerState<FlvpBackendBinder> createState() => _FlvpBackendBinderState();
}

class _FlvpBackendBinderState extends ConsumerState<FlvpBackendBinder> {
  late final _RiverpodBackend _backend = _RiverpodBackend(ref);

  void _pushProfiles() {
    widget.store.syncProfiles(
      _toSubInfos(
        ref.read(profilesProvider),
        ref.read(currentProfileIdProvider),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.store.backend = _backend;
    ref.listenManual(
      isStartProvider,
      (_, next) => widget.store.syncRunning(next),
    );
    ref.listenManual(
      networkSettingProvider.select((state) => state.systemProxy),
      (_, next) => widget.store.syncShortcuts(systemProxy: next),
    );
    ref.listenManual(
      patchClashConfigProvider.select((state) => state.tun.enable),
      (_, next) => widget.store.syncShortcuts(tunMode: next),
    );
    ref.listenManual(
      patchClashConfigProvider.select((state) => state.mode),
      (_, next) => widget.store.syncShortcuts(mode: _toFlvpMode(next)),
    );
    ref.listenManual(profilesProvider, (_, _) => _pushProfiles());
    ref.listenManual(currentProfileIdProvider, (_, _) => _pushProfiles());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final config = ref.read(patchClashConfigProvider);
      final network = ref.read(networkSettingProvider);
      widget.store.syncRunning(ref.read(isStartProvider));
      widget.store.syncShortcuts(
        systemProxy: network.systemProxy,
        tunMode: config.tun.enable,
        mode: _toFlvpMode(config.mode),
      );
      _pushProfiles();
    });
  }

  @override
  void dispose() {
    widget.store.backend = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RiverpodBackend implements FlvpBackend {
  _RiverpodBackend(this._ref);

  final WidgetRef _ref;

  @override
  Future<void> setRunning(bool value) async {
    await _ref
        .read(setupActionProvider.notifier)
        .setRunning(value, initialize: value && !_ref.read(initProvider));
  }

  @override
  Future<void> setSystemProxy(bool value) async {
    _ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: value));
  }

  @override
  Future<void> setTunMode(bool value) async {
    _ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: value));
  }

  @override
  Future<void> setMode(FlvpProxyMode value) async {
    if (_ref.read(patchClashConfigProvider).mode == _toMode(value)) return;
    _ref.read(setupActionProvider.notifier).changeMode(_toMode(value));
  }

  @override
  Future<void> addProfileFromLink(String url, String label) async {
    await _ref
        .read(profilesActionProvider.notifier)
        .addProfileFromLink(url, label: label.isEmpty ? null : label);
  }

  @override
  Future<void> deleteProfile(String id) async {
    final profileId = int.tryParse(id);
    if (profileId == null) return;
    await _ref.read(profilesActionProvider.notifier).deleteProfile(profileId);
  }

  @override
  Future<void> updateProfiles() async {
    await _ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
  }

  @override
  Future<void> setCurrentProfile(String id) async {
    final profileId = int.tryParse(id);
    if (profileId == null) return;
    if (_ref.read(currentProfileIdProvider) == profileId) return;
    _ref.read(currentProfileIdProvider.notifier).value = profileId;
  }
}