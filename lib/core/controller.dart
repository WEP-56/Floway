import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'compiler.dart';
import 'profile.dart';
import 'snapshot_store.dart';
import 'transport.dart';

class ClientController extends ChangeNotifier {
  ClientController({required this.store, required this.bridge});
  final SnapshotStore store;
  final CoreBridge bridge;
  final compiler = const ConfigCompiler();
  Profile profile = Profile.initial();
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

  Future<void> save(Profile candidate, {int? port, String? selection}) =>
      _execute(() async {
        final nextPort = port ?? mixedPort;
        var nextSelection = selection ?? selectedNodeId;
        if (nextSelection != null &&
            nextSelection != directTarget &&
            !candidate.nodes.any((node) => node.id == nextSelection)) {
          nextSelection = directTarget;
        }
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
          // Activation succeeded. Show the actual running settings even if a
          // disk failure prevents publication; keep the journal for recovery.
          profile = candidate;
          mixedPort = nextPort;
          selectedNodeId = nextSelection;
          await store.commit(
            bridge.status.appliedRevision,
            bridge.status.configHash!,
          );
        } else {
          await store.saveClientState(candidate, nextPort, nextSelection);
        }
        profile = candidate;
        mixedPort = nextPort;
        selectedNodeId = nextSelection;
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
