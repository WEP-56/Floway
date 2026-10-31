import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'compiler.dart';
import 'configuration_library.dart';
import 'configuration_importer.dart';
import 'elevated_host.dart';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'geo_resources.dart';
import 'profile.dart';
import 'rule_providers.dart';
import 'snapshot_store.dart';
import 'transport.dart';

class ClientController extends ChangeNotifier {
  ClientController({required this.store, required this.bridge});
  final SnapshotStore store;
  final CoreBridge bridge;
  final compiler = const ConfigCompiler();
  GeoResources get geoResources =>
      GeoResources(Directory(p.join(store.root.path, 'geo')));
  RuleProviderStore get ruleProviders =>
      RuleProviderStore(Directory(p.join(store.root.path, 'providers')));
  Profile profile = Profile.initial();
  ConfigurationLibrary library = ConfigurationLibrary();
  int mixedPort = 17890;
  String? selectedNodeId = directTarget;
  String? error;
  /// 最近一次导入/刷新被忽略的顶层字段、规则与 DNS 选项（逐项中文说明）。
  List<String> lastImportWarnings = const [];
  CoreState? transition;
  bool initialized = false;
  bool busy = false;
  bool _desiredRunning = false;
  bool _disposed = false;
  Timer? _poller;
  Future<void> _queue = Future.value();
  CoreState get state => transition ?? bridge.status.state;
  CoreStatus get status => bridge.status;
  bool get hostAvailable => bridge.capabilities != null;

  Future<void> refresh() => _execute(() async {
    if (hostAvailable) await bridge.refresh();
  }, quiet: true);

  Future<void> initialize() async {
    _poller?.cancel();
    await _execute(() async {
      await store.initialize();
      profile = await store.loadProfile();
      final device = await store.loadDeviceSettings();
      mixedPort = device['mixedPort'] as int;
      selectedNodeId =
          (device['selectedNodeId'] as String?) ??
          profile.nodes.firstOrNull?.id ??
          directTarget;
      if (selectedNodeId != null &&
          selectedNodeId != directTarget &&
          !profile.nodes.any((n) => n.id == selectedNodeId)) {
        selectedNodeId = directTarget;
      }
      library = await store.loadLibrary();
      // 上次退出时 TUN 仍开启：先连上协助进程，否则宿主会拒绝含 tun 的快照。
      if (profile.tun.enabled && Platform.isWindows) {
        try {
          await HelperClient.ensureRunning(
            defaultHostExecutable(),
            supportDirectory: store.root.path,
          );
          await bridge.switchTransport(ElevatedHostTransport());
        } catch (exception) {
          profile = profile.copyWith(tun: profile.tun.copyWith(enabled: false));
          // 回退也要同步活动配置，否则后续任何保存都会被
          // 「活动配置与运行源不一致」挡住。
          library = library.saveActive(
            profile,
            selectedNodeId ?? directTarget,
          );
          error = 'TUN 未能恢复（${exception.toString()}），已回退为普通代理';
        }
      }
      await bridge.initialize();
      _desiredRunning = bridge.status.running;
      if (await store.hasPending()) {
        if (bridge.status.running) {
          await store.commit(
            bridge.status.appliedRevision,
            bridge.status.configHash!,
          );
        } else {
          await store.clearPending();
        }
        profile = await store.loadProfile();
        library = await store.loadLibrary();
        final recovered = await store.loadDeviceSettings();
        mixedPort = recovered['mixedPort'] as int;
        selectedNodeId =
            (recovered['selectedNodeId'] as String?) ??
            profile.nodes.firstOrNull?.id ??
            directTarget;
      }
    });
    initialized = true;
    _notify();
    _poller = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!busy && !_disposed && hostAvailable) {
        unawaited(
          _execute(() async {
            await bridge.refresh();
          }, quiet: true),
        );
      }
    });
  }

  Future<void> _execute(Future<void> Function() action, {bool quiet = false}) {
    final completion = Completer<void>();
    _queue = _queue.then((_) async {
      if (_disposed) {
        completion.complete();
        return;
      }
      busy = true;
      if (!quiet) error = null;
      _notify();
      try {
        await action();
      } catch (exception) {
        error = exception.toString();
        if (exception is HostTransportException) {
          bridge.status = const CoreStatus(state: CoreState.failed);
          bridge.capabilities = null;
          _desiredRunning = false;
        }
      } finally {
        transition = null;
        busy = false;
        _notify();
        completion.complete();
      }
    });
    return completion.future;
  }

  Future<void> connect() {
    _desiredRunning = true;
    return _execute(() async {
      if (!hostAvailable) await bridge.initialize();
      if (!_desiredRunning || bridge.status.running) return;
      transition = CoreState.preparing;
      _notify();
      final config = compiler.compile(
        profile,
        mixedPort: mixedPort,
        selectedNodeId: selectedNodeId,
      );
      final snapshot = await store.stage(
        config,
        profile: profile,
        selectedNodeId: selectedNodeId,
        library: library,
      );
      if (!_desiredRunning) return;
      await store.beginApply(snapshot, bridge.status.appliedRevision);
      transition = CoreState.starting;
      _notify();
      await bridge.start(snapshot);
      if (_desiredRunning) {
        await store.commit(
          bridge.status.appliedRevision,
          bridge.status.configHash!,
        );
      }
    });
  }

  Future<void> stop() {
    _desiredRunning = false;
    transition = CoreState.stopping;
    _notify();
    return _execute(() async {
      if (!hostAvailable) {
        transition = null;
        return;
      }
      await bridge.stop();
      await store.clearPending();
    });
  }

  bool get tunEnabled => profile.tun.enabled;

  /// 开启/关闭 TUN。首次开启会安装管理员协助进程（一次 UAC），
  /// 之后走常驻进程静默连接；TUN 与系统代理互斥。
  Future<void> setTun(bool enabled) async {
    await _execute(() async {
      if (enabled == profile.tun.enabled && bridge.status.running) {
        return;
      }
      final previousProfile = profile;
      final previousLibrary = library;
      final previousSelection = selectedNodeId ?? directTarget;
      try {
        if (enabled) {
          await HelperClient.ensureRunning(
            defaultHostExecutable(),
            supportDirectory: store.root.path,
          );
          await bridge.switchTransport(ElevatedHostTransport());
        } else {
          // 先让协助进程停下它的核心并清理 TUN 路由，再切回普通宿主。
          // 直接切走会把 TUN 和路由留在系统里，而新宿主根本不知道它们的存在。
          if (bridge.transport is ElevatedHostTransport) {
            try {
              await bridge.stop();
            } catch (_) {
              // 协助进程已消失时 stop 必然失败；路由由新宿主的启动恢复兜底。
            }
          }
          await bridge.switchTransport(
            WindowsHostTransport(supportDirectory: store.root.path),
          );
        }
        await bridge.initialize();
        final selection = selectedNodeId ?? directTarget;
        final next = profile.copyWith(
          tun: profile.tun.copyWith(enabled: enabled, autoRoute: enabled),
        );
        // 配置仓库里的活动条目必须一起更新：store 会校验
        // 「活动配置 == 运行源」，只改 profile 会直接抛
        // 「活动配置与运行源不一致」，而此时旧宿主已经被切走了。
        final nextLibrary = library.saveActive(next, selection);
        await store.saveClientState(
          next,
          mixedPort,
          selection,
          library: nextLibrary,
        );
        profile = next;
        library = nextLibrary;
        if (!_desiredRunning) return;
        final config = compiler.compile(
          next,
          mixedPort: mixedPort,
          selectedNodeId: selection,
        );
        final snapshot = await store.stage(
          config,
          profile: next,
          selectedNodeId: selection,
          library: nextLibrary,
        );
        await store.beginApply(snapshot, bridge.status.appliedRevision);
        transition = CoreState.starting;
        _notify();
        await bridge.start(snapshot);
        await store.commit(
          bridge.status.appliedRevision,
          bridge.status.configHash!,
        );
      } catch (_) {
        // 切换传输会关掉原宿主，所以失败时必须自己把用户送回可用状态，
        // 否则表现就是「一开 TUN 连接就被关掉」，且再也起不来。
        profile = previousProfile;
        library = previousLibrary;
        await _restoreAfterTunFailure(previousProfile, previousLibrary, previousSelection);
        rethrow;
      }
    });
    if (error != null) throw StateError(error!);
  }

  /// TUN 切换失败后回到普通宿主，并按原配置重新拉起代理。
  /// 每一步都单独兜底：这里已经在错误路径上，不能再抛出新错误盖住原因。
  Future<void> _restoreAfterTunFailure(
    Profile previousProfile,
    ConfigurationLibrary previousLibrary,
    String selection,
  ) async {
    try {
      // 失败发生在切换之前（例如用户取消了 UAC）：原宿主还在正常跑，
      // 此时重新 start 只会撞 ALREADY_RUNNING，直接返回即可。
      if (bridge.transport is! ElevatedHostTransport && bridge.status.running) {
        return;
      }
      if (bridge.transport is ElevatedHostTransport) {
        try {
          await bridge.stop();
        } catch (_) {}
        await bridge.switchTransport(
          WindowsHostTransport(supportDirectory: store.root.path),
        );
        await bridge.initialize();
      }
      if (!_desiredRunning) return;
      await store.saveClientState(
        previousProfile,
        mixedPort,
        selection,
        library: previousLibrary,
      );
      final config = compiler.compile(
        previousProfile,
        mixedPort: mixedPort,
        selectedNodeId: selection,
      );
      final snapshot = await store.stage(
        config,
        profile: previousProfile,
        selectedNodeId: selection,
        library: previousLibrary,
      );
      await store.beginApply(snapshot, bridge.status.appliedRevision);
      await bridge.start(snapshot);
      await store.commit(
        bridge.status.appliedRevision,
        bridge.status.configHash!,
      );
    } catch (_) {
      // 回滚失败时保留原始错误；用户仍可手动重连。
    }
  }

  /// 卸载管理员协助进程并回到普通宿主；TUN 会同时关闭。\r
  Future<void> uninstallTunHelper() async {
    await _execute(() async {
      final selection = selectedNodeId ?? directTarget;
      final next = profile.copyWith(tun: const TunOptions.disabled());
      // 与 setTun 同理：活动配置必须同步，否则 store 校验会拒绝。
      final nextLibrary = library.saveActive(next, selection);
      await store.saveClientState(
        next,
        mixedPort,
        selection,
        library: nextLibrary,
      );
      profile = next;
      library = nextLibrary;
      if (bridge.transport is ElevatedHostTransport) {
        await bridge.switchTransport(
          WindowsHostTransport(supportDirectory: store.root.path),
        );
        await bridge.initialize();
      }
      await HelperClient.uninstall();
    });
    if (error != null) throw StateError(error!);
  }

  Future<void> setSystemProxy(bool enabled) async {
    if (enabled && profile.tun.enabled) {
      throw StateError('TUN 与系统代理互斥，请先关闭 TUN');
    }
    await _execute(() async {
      if (!bridge.status.running && enabled) {
        throw const CoreFailure('NOT_RUNNING', '请先启动本地代理', null);
      }
      await bridge.setSystemProxy(enabled);
    });
    if (error != null) throw StateError(error!);
  }

  Future<void> save(Profile candidate, {int? port, String? selection}) =>
      _execute(() => _save(candidate, port: port, selection: selection));

  Future<void> _save(
    Profile candidate, {
    int? port,
    String? selection,
    ConfigurationLibrary? nextLibrary,
  }) async {
    final nextPort = port ?? mixedPort;
    var nextSelection = selection ?? selectedNodeId ?? directTarget;
    if (nextSelection != directTarget &&
        !candidate.nodes.any((node) => node.id == nextSelection)) {
      nextSelection = directTarget;
    }
    final candidateLibrary = (nextLibrary ?? library).saveActive(
      candidate,
      nextSelection,
    );
    candidateLibrary.validate();
    final config = compiler.compile(
      candidate,
      mixedPort: nextPort,
      selectedNodeId: nextSelection,
    );
    if (bridge.status.running) {
      final snapshot = await store.stage(
        config,
        profile: candidate,
        selectedNodeId: nextSelection,
        library: candidateLibrary,
      );
      await store.beginApply(snapshot, bridge.status.appliedRevision);
      transition = CoreState.applying;
      _notify();
      try {
        await bridge.apply(snapshot);
      } catch (_) {
        if (bridge.status.running) {
          await store.commit(
            bridge.status.appliedRevision,
            bridge.status.configHash!,
          );
        }
        rethrow;
      }
      // Reflect actual running state even when publishing to disk fails.
      profile = candidate;
      mixedPort = nextPort;
      selectedNodeId = nextSelection;
      library = candidateLibrary;
      await store.commit(
        bridge.status.appliedRevision,
        bridge.status.configHash!,
      );
    } else {
      await store.saveClientState(
        candidate,
        nextPort,
        nextSelection,
        library: candidateLibrary,
      );
    }
    profile = candidate;
    mixedPort = nextPort;
    selectedNodeId = nextSelection;
    library = candidateLibrary;
  }

  static List<String> _compressWarnings(List<String> raw) {
    final counts = <String, int>{};
    for (final item in raw) {
      counts[item] = (counts[item] ?? 0) + 1;
    }
    return List.unmodifiable([
      for (final entry in counts.entries)
        entry.value == 1 ? entry.key : '${entry.key}（${entry.value} 处）',
    ]);
  }

  Future<void> importConfiguration(
    String name,
    ConfigurationSourceKind kind, {
    String? text,
    String? url,
    Profile? manualProfile,
  }) => _execute(() async {
    requireConfig(
      name.trim().isNotEmpty && name.length <= 100,
      '配置名称需为 1–100 个字符',
    );
    final original = kind == ConfigurationSourceKind.remote
        ? await const SubscriptionFetcher().fetch(url!)
        : text ?? canonicalJson(manualProfile!.toJson());
    final sourceId = const Uuid().v4();
    await ruleProviders.ensureFor(sourceId, original);
    final warnings = <String>[];
    final parsed =
        manualProfile ??
        const ConfigurationImporter().parse(
          original,
          name: name,
          warnings: warnings,
        );
    lastImportWarnings = _compressWarnings(warnings);
    await geoResources.ensureFor(parsed);
    final selected = parsed.nodes.firstOrNull?.id ?? directTarget;
    compiler.compile(parsed, mixedPort: mixedPort, selectedNodeId: selected);
    final entry = ConfigurationSource(
      id: sourceId,
      name: name,
      kind: kind,
      original: original,
      profile: parsed,
      selectedNodeId: selected,
      updatedAt: DateTime.now().toUtc(),
      url: url,
    );
    final next = library.upsert(entry, activate: library.activeId == null);
    next.validate();
    if (next.activeId == entry.id) {
      await _save(parsed, selection: selected, nextLibrary: next);
    } else {
      await store.saveClientState(
        profile,
        mixedPort,
        selectedNodeId,
        library: next,
      );
      library = next;
    }
  });

  Future<void> activateConfiguration(String id) => _execute(() async {
    final next = library.select(id);
    final source = next.active!;
    if (!await ruleProviders.activate(source.id)) {
      await ruleProviders.ensureFor(source.id, source.original);
    }
    await _save(
      source.profile,
      selection: source.selectedNodeId,
      nextLibrary: next,
    );
  });

  Future<void> removeConfiguration(String id) => _execute(() async {
    await ruleProviders.forget(id);
    final next = library.remove(id);
    await store.saveClientState(
      profile,
      mixedPort,
      selectedNodeId,
      library: next,
    );
    library = next;
  });

  Future<void> refreshConfiguration(String id) => _execute(() async {
    final old = library.source(id);
    requireConfig(old.kind == ConfigurationSourceKind.remote, '本地配置无需远程更新');
    final original = await const SubscriptionFetcher().fetch(old.url!);
    const importer = ConfigurationImporter();
    await ruleProviders.ensureFor(old.id, original);
    final warnings = <String>[];
    final parsed = importer.reconcile(
      importer.parse(original, name: old.name, warnings: warnings),
      old,
    );
    lastImportWarnings = _compressWarnings(warnings);
    await geoResources.ensureFor(parsed);
    compiler.compile(
      parsed,
      mixedPort: mixedPort,
      selectedNodeId: old.selectedNodeId,
    );
    final entry = ConfigurationSource(
      id: old.id,
      name: old.name,
      kind: old.kind,
      original: original,
      profile: parsed,
      selectedNodeId: old.selectedNodeId,
      updatedAt: DateTime.now().toUtc(),
      url: old.url,
    );
    final next = library.upsert(entry);
    next.validate();
    if (next.activeId == id) {
      await _save(parsed, selection: old.selectedNodeId, nextLibrary: next);
    } else {
      await store.saveClientState(
        profile,
        mixedPort,
        selectedNodeId,
        library: next,
      );
      library = next;
    }
  });

  Future<void> close() async {
    _poller?.cancel();
    await stop();
    await bridge.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller?.cancel();
    super.dispose();
  }
}
