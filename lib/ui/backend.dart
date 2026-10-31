import 'package:floway/enum/enum.dart';
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
}