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

  /// 仪表盘上的“当前节点”：优先取 GLOBAL 组的实际出口，没有内核节点时清空。
  ///
  /// 上游在构建期也会推 groups，直接 notifyListeners 会撞上 "setState during
  /// build"，所以统一推迟到帧后。
  void _pushCurrentNode(List<Group> groups) {
    final group = groups.where((item) => item.name == 'GLOBAL').firstOrNull ??
        groups.firstOrNull;
    final name = group?.now;
    final proxy = group == null || name == null || name.isEmpty
        ? null
        : group.all.where((item) => item.name == name).firstOrNull;
    final rawDelay = name == null ? null : ref.read(delayProvider(proxyName: name));
    final node = group == null || name == null || name.isEmpty
        ? null
        : NodeInfo(
            id: name,
            name: name,
            sub: group.name,
            proto: (proxy?.type ?? '').toUpperCase(),
            region: '',
            // 负数表示没测出来，仪表盘按“无延迟”处理。
            latency: rawDelay != null && rawDelay > 0 ? rawDelay : null,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.store.syncCurrentNode(node);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.store.backend = _backend;
    ref.listenManual(isStartProvider, (_, next) {
      widget.store.syncRunning(next);
      // 停止后上游不再给出口节点，界面不该继续显示上一次的节点。
      if (!next) widget.store.syncCurrentNode(null);
    });
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
    ref.listenManual(
      delayTestingGroupsProvider,
      (_, next) => widget.store.syncDelayTesting(next.isNotEmpty),
      fireImmediately: true,
    );
    ref.listenManual(trafficsProvider, (_, next) {
      if (next.length == 0) return;
      final sample = next[next.length - 1];
      widget.store.syncTraffic(
        upKb: sample.up / 1024,
        downKb: sample.down / 1024,
      );
    });
    ref.listenManual(totalTrafficProvider, (_, next) {
      widget.store.syncTotals(
        up: next.up / _bytesPerGb,
        down: next.down / _bytesPerGb,
      );
    });
    ref.listenManual(runTimeProvider, (_, next) {
      if (next == null) return;
      // 上游 runTime 是毫秒。
      widget.store.syncUptime(next ~/ 1000);
    });
    ref.listenManual(
      groupsProvider,
      (_, next) => _pushCurrentNode(next),
    );
    ref.listenManual(
      delayDataSourceProvider,
      (_, _) => _pushCurrentNode(ref.read(groupsProvider)),
    );
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
      _pushCurrentNode(ref.read(groupsProvider));
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
    // 界面上的“更新全部”要更新所有远程配置，不只是到期的那几份。
    await _ref.read(profilesActionProvider.notifier).updateProfiles();
  }

  @override
  Future<void> setCurrentProfile(String id) async {
    final profileId = int.tryParse(id);
    if (profileId == null) return;
    if (_ref.read(currentProfileIdProvider) == profileId) return;
    _ref.read(currentProfileIdProvider.notifier).value = profileId;
  }

  @override
  Future<void> testDelay() async {
    final groups = _ref.read(groupsProvider);
    if (groups.isEmpty) return;
    // delayTestGroups 本身不标记 testing，这里补上，界面的“测试中”才有依据。
    final testing = _ref.read(delayTestingGroupsProvider.notifier);
    final started = [
      for (final group in groups)
        if (testing.start(group.name)) group.name,
    ];
    try {
      await _ref.read(proxiesActionProvider.notifier).delayTestGroups(groups);
    } finally {
      for (final name in started) {
        testing.stop(name);
      }
    }
  }
}