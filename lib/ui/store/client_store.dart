import 'dart:async';

import '../../core/controller.dart';
import '../../core/profile.dart';
import '../../core/traffic.dart';
import 'design_store.dart';
import 'models.dart';

/// Connects the design's existing action/data contract to the native runtime.
/// FlvpDesignStore remains the isolated, injectable design preview.
class FlvpClientStore extends FlvpDesignStore {
  FlvpClientStore(this.controller)
    : super(
        simulate: false,
        settings: const AppSettings(
          autoStart: false,
          silentStart: false,
          autoConnect: false,
          closeBehavior: FlvpCloseBehavior.quit,
          mixedPort: '17890',
          socksPort: '17890',
          systemProxy: false,
          dns: '',
          sniff: false,
          logLevel: 'warn',
        ),
      ) {
    running = false;
    uptime = 0;
    nodes = [_direct];
    selectedNodeId = directTarget;
    subs = [];
    hist['up'] = List.filled(flvpHistLength, 0);
    hist['down'] = List.filled(flvpHistLength, 0);
    controller.addListener(_onController);
    _clock.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      clock = DateTime.now();
      uptime = _traffic.uptime(_clock.elapsed);
      if (!_traffic.fresh(_clock.elapsed)) speed = (up: 0, down: 0);
      hist['up'] = [...hist['up']!.skip(1), speed.up];
      hist['down'] = [...hist['down']!.skip(1), speed.down];
      notifyListeners();
    });
  }

  static const _direct = NodeInfo(
    id: directTarget,
    name: 'DIRECT',
    sub: '内置策略',
    proto: 'DIRECT',
    region: '',
  );
  final ClientController controller;
  final _traffic = TrafficTracker();
  final _clock = Stopwatch();
  Timer? _ticker;
  Timer? _portTimer;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool _closing = false;
  bool _connecting = false;
  int _draftVersion = 0;
  String? _shownError;
  Object? _lastStatus;

  Future<void> initializeClient() async {
    await controller.initialize();
    if (_disposed) return;
    _syncConfiguration();
    _onController();
  }

  void _syncConfiguration({bool syncSettings = true}) {
    nodes = [
      _direct,
      for (final node in controller.profile.nodes)
        NodeInfo(
          id: node.id,
          name: node.displayName,
          sub: '本地节点',
          proto: node.protocol.name.toUpperCase(),
          region: '',
        ),
    ];
    selectedNodeId = controller.selectedNodeId ?? directTarget;
    if (!syncSettings) return;
    super.setSettings(
      (s) => s.copyWith(
        mode: FlvpProxyMode.values.byName(controller.profile.mode.name),
        mixedPort: '${controller.mixedPort}',
        socksPort: '${controller.mixedPort}',
      ),
    );
  }

  void _onController() {
    if (_disposed) return;
    running = controller.status.running;
    if (!identical(_lastStatus, controller.status)) {
      _lastStatus = controller.status;
      _traffic.sample(controller.status, _clock.elapsed);
      speed = (
        up: _traffic.uploadRate / 1024,
        down: _traffic.downloadRate / 1024,
      );
    }
    if (controller.error != null && controller.error != _shownError) {
      _shownError = controller.error;
      notify(controller.error!);
    } else {
      if (controller.error == null) _shownError = null;
      notifyListeners();
    }
  }

  @override
  FlvpTraffic get traffic => settings.statsScope == FlvpStatsScope.total
      ? FlvpTraffic(
          up: _traffic.totalUpload / 1e9,
          down: _traffic.totalDownload / 1e9,
        )
      : FlvpTraffic(
          up: _traffic.sessionUpload / 1e9,
          down: _traffic.sessionDownload / 1e9,
        );

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed || _closing) return Future.value();
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (error) {
        if (!_disposed) notify(error.toString());
      }
    });
    return _queue;
  }

  @override
  Future<void> toggleRunning() async {
    if (_disposed || _closing) return;
    if (!controller.initialized) {
      notify('内核正在初始化');
      return;
    }
    // A second power press while native start is in flight is an explicit
    // cancellation. ClientController makes stop win over pending start.
    if (running || _connecting) {
      _connecting = false;
      await controller.stop();
      return;
    }
    _connecting = true;
    await flushSettings();
    if (!_connecting || _disposed || _closing) return;
    try {
      await controller.connect();
      if (!_disposed && controller.error == null && running) {
        notify('本地代理已启动');
      }
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> selectNode(String id) async {
    if (_disposed || _closing) return;
    if (id != directTarget &&
        !controller.profile.nodes.any((n) => n.id == id)) {
      notify('选择的节点已不存在');
      return;
    }
    await flushSettings();
    await _enqueue(() async {
      final version = _draftVersion;
      await controller.save(controller.profile, selection: id);
      if (_disposed) return;
      _syncConfiguration(syncSettings: _draftVersion == version);
      if (controller.error == null) notify('已切换到 ${currentNode.name}');
    });
  }

  @override
  void setSettings(AppSettings Function(AppSettings current) mutate) {
    if (_disposed || _closing) return;
    final before = settings;
    final next = mutate(before);
    if (!controller.initialized &&
        (next.mode != before.mode || next.mixedPort != before.mixedPort)) {
      notify('内核正在初始化');
      return;
    }
    final unsupported = _unsupportedChange(before, next);
    if (unsupported != null) {
      notify('$unsupported尚未实现');
      return;
    }
    super.setSettings((_) => next);
    if (next.mode != before.mode || next.mixedPort != before.mixedPort) {
      _draftVersion++;
      _portTimer?.cancel();
      // Fields report every keystroke; only apply a complete, settled value.
      _portTimer = Timer(const Duration(milliseconds: 650), () {
        _portTimer = null;
        unawaited(_saveSettings());
      });
    }
  }

  String? _unsupportedChange(AppSettings a, AppSettings b) {
    if (a.systemProxy != b.systemProxy) return '系统代理';
    if (a.tunMode != b.tunMode) return 'TUN / VPN';
    if (a.allowLan != b.allowLan) return '局域网监听';
    if (a.socksPort != b.socksPort) return '独立 SOCKS 端口（请使用混合端口）';
    if (a.dns != b.dns ||
        a.sniff != b.sniff ||
        a.ipv6 != b.ipv6 ||
        a.logLevel != b.logLevel ||
        a.stack != b.stack) {
      return '此内核参数的动态配置';
    }
    if (a.autoStart != b.autoStart ||
        a.silentStart != b.silentStart ||
        a.autoConnect != b.autoConnect) {
      return '自动启动';
    }
    if (a.closeBehavior != b.closeBehavior) return '托盘驻留';
    if (a.language != b.language) return '多语言切换';
    return null;
  }

  Future<void> _saveSettings() {
    final version = _draftVersion;
    final port = int.tryParse(settings.mixedPort);
    final mode = RoutingMode.values.byName(settings.mode.name);
    if (port == null || port < 1024 || port > 65535) {
      _syncConfiguration();
      notify('本地代理端口必须为 1024–65535');
      return Future.value();
    }
    return _enqueue(() async {
      await controller.save(
        controller.profile.copyWith(mode: mode),
        port: port,
      );
      if (_disposed) return;
      // A later draft must survive completion of an earlier native apply.
      if (_draftVersion == version) _syncConfiguration();
    });
  }

  Future<void> flushSettings() async {
    if (_portTimer != null) {
      _portTimer!.cancel();
      _portTimer = null;
      await _saveSettings();
    }
    await _queue;
  }

  @override
  void testNodes() => notify('节点延迟测试尚未实现');
  @override
  void importSub(String name, String url) => notify('订阅导入尚未实现，当前使用已保存的本地配置');
  @override
  void activateSub(String id) => notify('订阅切换尚未实现');
  @override
  void refreshSub(String id) => notify('订阅更新尚未实现');
  @override
  void refreshAllSubs() => notify('订阅更新尚未实现');
  @override
  void removeSub(String id) => notify('订阅管理尚未实现');

  Future<void> close() async {
    if (_closing) return;
    await flushSettings();
    _closing = true;
    _connecting = false;
    try {
      await controller.close();
    } catch (_) {
      _closing = false;
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _portTimer?.cancel();
    _clock.stop();
    controller.removeListener(_onController);
    super.dispose();
  }
}
