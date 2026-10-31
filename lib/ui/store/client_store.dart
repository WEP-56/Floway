import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../../core/configuration_library.dart';
import '../../core/configuration_importer.dart';

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
  String? _shownNetworkRecoveryError;

  Future<void> initializeClient() async {
    await controller.initialize();
    if (_disposed) return;
    _syncConfiguration();
    _onController();
  }

  void _syncConfiguration({bool syncSettings = true}) {
    final targetNames = {
      directTarget: 'DIRECT',
      rejectTarget: 'REJECT',
      for (final n in controller.profile.nodes) n.id: n.displayName,
      for (final g in controller.profile.groups) g.id: g.displayName,
    };
    policyGroups = [
      for (final g in controller.profile.groups)
        PolicyGroupInfo(
          id: g.id,
          name: g.displayName,
          type: g.coreType,
          members: {for (final id in g.members) id: targetNames[id]!},
          selectedId:
              g.selectedId ??
              (g.kind == GroupKind.select ? g.members.first : null),
        ),
    ];
    nodes = [
      _direct,
      for (final node in controller.profile.nodes)
        NodeInfo(
          id: node.id,
          name: node.displayName,
          sub: controller.library.active?.name ?? '本地配置',
          proto: node.protocol.name.toUpperCase(),
          region: '',
        ),
    ];
    subs = [
      for (final source in controller.library.sources)
        SubInfo(
          id: source.id,
          name: source.name,
          url: source.kind == ConfigurationSourceKind.remote
              ? Uri.parse(source.url!).host
              : (source.kind == ConfigurationSourceKind.file
                    ? '本地文件快照'
                    : '手动配置'),
          used: 0,
          total: 0,
          expire: '',
          updated: source.updatedAt.toLocal().toString().substring(0, 16),
          active: source.id == controller.library.activeId,
          remote: source.kind == ConfigurationSourceKind.remote,
          hasQuota: false,
        ),
    ];
    selectedNodeId = controller.selectedNodeId ?? directTarget;
    if (!syncSettings) return;
    super.setSettings(
      (s) => s.copyWith(
        mode: FlvpProxyMode.values.byName(controller.profile.mode.name),
        mixedPort: '${controller.mixedPort}',
        socksPort: '${controller.mixedPort}',
        systemProxy: controller.status.systemProxy,
      ),
    );
  }

  void _onController() {
    if (_disposed) return;
    running = controller.status.running;
    if (settings.systemProxy != controller.status.systemProxy) {
      super.setSettings(
        (s) => s.copyWith(systemProxy: controller.status.systemProxy),
      );
    }
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
    } else if (controller.status.systemProxyRecoveryError != null &&
        controller.status.systemProxyRecoveryError !=
            _shownNetworkRecoveryError) {
      _shownNetworkRecoveryError = controller.status.systemProxyRecoveryError;
      notify(controller.status.systemProxyRecoveryError!);
    } else {
      if (controller.error == null) _shownError = null;
      if (controller.status.systemProxyRecoveryError == null) {
        _shownNetworkRecoveryError = null;
      }
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
  Future<void> selectGroupMember(String groupId, String memberId) async {
    if (_disposed || _closing) return;
    await flushSettings();
    await _enqueue(() async {
      final version = _draftVersion;
      final group = controller.profile.groups
          .where((g) => g.id == groupId)
          .firstOrNull;
      if (group == null ||
          group.kind != GroupKind.select ||
          !group.members.contains(memberId)) {
        notify('策略组或成员已不存在');
        return;
      }
      await controller.save(
        controller.profile.copyWith(
          groups: [
            for (final g in controller.profile.groups)
              g.id == groupId ? g.select(memberId) : g,
          ],
        ),
      );
      if (_disposed) return;
      _syncConfiguration(syncSettings: _draftVersion == version);
      if (controller.error == null) notify('策略组选择已保存');
    });
  }

  @override
  void setSettings(AppSettings Function(AppSettings current) mutate) {
    if (_disposed || _closing) return;
    final before = settings;
    final next = mutate(before);
    if (!controller.initialized &&
        (next.mode != before.mode ||
            next.mixedPort != before.mixedPort ||
            next.systemProxy != before.systemProxy)) {
      notify('内核正在初始化');
      return;
    }
    final unsupported = _unsupportedChange(before, next);
    if (unsupported != null) {
      notify('$unsupported尚未实现');
      return;
    }
    if (next.tunMode != before.tunMode) {
      final caps = controller.bridge.capabilities ?? const <String, dynamic>{};
      if (next.tunMode &&
          (!Platform.isWindows ||
              (caps['tun'] != true && caps['tunInstallable'] != true))) {
        notify('TUN 需要管理员宿主，当前宿主不支持');
        return;
      }
      unawaited(
        _enqueue(() async {
          try {
            await controller.setTun(next.tunMode);
            if (!_disposed) {
              super.setSettings(
                (s) => s.copyWith(
                  tunMode: controller.tunEnabled,
                  systemProxy: controller.status.systemProxy,
                ),
              );
              notify(
                next.tunMode
                    ? 'TUN 已开启（首次需在系统弹窗中授权）'
                    : 'TUN 已关闭，已回到普通代理',
              );
            }
          } catch (error) {
            if (!_disposed) {
              super.setSettings((s) => s.copyWith(tunMode: controller.tunEnabled));
              notify(error.toString());
            }
          }
        }),
      );
      return;
    }
    if (next.systemProxy != before.systemProxy) {
      if (controller.bridge.capabilities?['systemProxy'] != true) {
        notify('系统代理仅支持 Windows');
        return;
      }
      if (next.systemProxy && !controller.status.running) {
        notify('请先启动本地代理，再启用系统代理');
        return;
      }
      unawaited(
        _enqueue(() async {
          try {
            await controller.setSystemProxy(next.systemProxy);
            if (!_disposed) {
              super.setSettings(
                (s) => s.copyWith(systemProxy: controller.status.systemProxy),
              );
              notify(next.systemProxy ? '系统代理已开启' : '系统代理已恢复');
            }
          } catch (error) {
            if (!_disposed) {
              super.setSettings(
                (s) => s.copyWith(systemProxy: controller.status.systemProxy),
              );
              notify(error.toString());
            }
          }
        }),
      );
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
  Future<bool> _configurationAction(
    Future<void> Function() action,
    String success,
  ) async {
    if (_disposed || _closing || !controller.initialized) return false;
    if (_portTimer != null) {
      _portTimer!.cancel();
      _portTimer = null;
      unawaited(_saveSettings());
    }
    var completed = false;
    await _enqueue(() async {
      final version = _draftVersion;
      await action();
      if (_disposed) return;
      _syncConfiguration(syncSettings: _draftVersion == version);
      completed = controller.error == null;
      if (completed) {
        final ignored = controller.lastImportWarnings;
        if (ignored.isEmpty) {
          notify(success);
        } else {
          final head = ignored.take(3).join('；');
          final more = ignored.length > 3 ? ' 等 ${ignored.length} 项' : '';
          notify('$success；已忽略：$head$more');
        }
      }
    });
    return completed;
  }

  @override
  void importSub(String name, String url) {
    unawaited(importRemoteConfiguration(name, url));
  }

  @override
  Future<bool> importRemoteConfiguration(String name, String url) =>
      _configurationAction(
        () => controller.importConfiguration(
          name,
          ConfigurationSourceKind.remote,
          url: url,
        ),
        '订阅已导入',
      );

  @override
  Future<bool> importFileConfiguration(String name) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '代理配置',
            extensions: ['json', 'yaml', 'yml', 'txt'],
          ),
        ],
      );
      if (file == null || _disposed || _closing) return false;
      requireConfig(await file.length() <= maxImportBytes, '配置文件超过 1 MiB');
      final text = utf8.decode(await file.readAsBytes());
      return await _configurationAction(
        () => controller.importConfiguration(
          name,
          ConfigurationSourceKind.file,
          text: text,
        ),
        '本地配置已导入',
      );
    } on ConfigurationException catch (error) {
      notify(error.message);
    } catch (_) {
      notify('文件读取失败，请选择可读取的 UTF-8 配置文件');
    }
    return false;
  }

  @override
  Future<bool> createManualConfiguration(
    String name,
    String protocol,
    String server,
    String port,
  ) async {
    try {
      final number = int.tryParse(port);
      requireConfig(number != null, '端口必须是整数');
      final profile = const ConfigurationImporter().manual(
        name,
        enumValue(NodeProtocol.values, protocol, '节点协议'),
        server,
        number!,
      );
      return await _configurationAction(
        () => controller.importConfiguration(
          name,
          ConfigurationSourceKind.manual,
          manualProfile: profile,
        ),
        '手动配置已创建',
      );
    } on ConfigurationException catch (error) {
      notify(error.message);
      return false;
    }
  }

  @override
  void activateSub(String id) {
    unawaited(
      _configurationAction(
        () => controller.activateConfiguration(id),
        '已切换活动配置',
      ),
    );
  }

  @override
  Future<void> refreshSub(String id) async {
    await _configurationAction(
      () => controller.refreshConfiguration(id),
      '订阅已更新',
    );
  }

  @override
  void refreshAllSubs() {
    unawaited(_refreshRemoteSources());
  }

  Future<void> _refreshRemoteSources() async {
    for (final source
        in controller.library.sources
            .where((s) => s.kind == ConfigurationSourceKind.remote)
            .toList()) {
      await _configurationAction(
        () => controller.refreshConfiguration(source.id),
        '已更新「${source.name}」',
      );
    }
  }

  @override
  void removeSub(String id) {
    unawaited(
      _configurationAction(() => controller.removeConfiguration(id), '配置已删除'),
    );
  }

  @override
  Future<void> copySubscriptionUrl(String id) async {
    final source = controller.library.source(id);
    if (source.url == null) {
      notify('本地配置没有订阅链接');
      return;
    }
    await Clipboard.setData(ClipboardData(text: source.url!));
    if (!_disposed) notify('订阅链接已复制');
  }

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
