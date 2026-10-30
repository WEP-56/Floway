import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'compiler.dart';
import 'configuration_library.dart';
import 'configuration_importer.dart';

import 'package:uuid/uuid.dart';

import 'profile.dart';
import 'snapshot_store.dart';
import 'transport.dart';

class ClientController extends ChangeNotifier {
  ClientController({required this.store, required this.bridge});
  final SnapshotStore store;
  final CoreBridge bridge;
  final compiler = const ConfigCompiler();
  Profile profile = Profile.initial();
  ConfigurationLibrary library = ConfigurationLibrary();
  int mixedPort = 17890;
  String? selectedNodeId = directTarget;
  String? error;
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

  Future<void> setSystemProxy(bool enabled) async {
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
    final parsed =
        manualProfile ??
        const ConfigurationImporter().parse(original, name: name);
    final selected = parsed.nodes.firstOrNull?.id ?? directTarget;
    compiler.compile(parsed, mixedPort: mixedPort, selectedNodeId: selected);
    final entry = ConfigurationSource(
      id: const Uuid().v4(),
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
    await _save(
      source.profile,
      selection: source.selectedNodeId,
      nextLibrary: next,
    );
  });

  Future<void> removeConfiguration(String id) => _execute(() async {
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
    final parsed = importer.reconcile(
      importer.parse(original, name: old.name),
      old,
    );
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
