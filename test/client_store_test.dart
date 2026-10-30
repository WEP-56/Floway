import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/ui/store/client_store.dart';
import 'package:flvpcore/ui/store/models.dart';

import 'fake_host.dart';

const node = ProxyNode(
  id: '97bf1420-1849-4963-96c8-d836aa75a5c5',
  displayName: '已保存 HTTP 节点',
  protocol: NodeProtocol.http,
  server: '127.0.0.1',
  port: 8080,
);

void main() {
  late Directory root;
  late FakeHost host;
  late ClientController controller;
  late FlvpClientStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flvp-client-store-');
    final snapshots = SnapshotStore(root);
    await snapshots.initialize();
    await snapshots.saveClientState(
      Profile.initial().copyWith(nodes: [node]),
      17932,
      node.id,
    );
    host = FakeHost();
    controller = ClientController(store: snapshots, bridge: CoreBridge(host));
    store = FlvpClientStore(controller);
    await store.initializeClient();
  });
  tearDown(() async {
    store.dispose();
    await controller.close();
    controller.dispose();
    await root.delete(recursive: true);
  });

  test(
    'loads existing nodes and port without overwriting disk or demo data',
    () async {
      expect(store.running, isFalse);
      expect(store.nodes.map((n) => n.id), [directTarget, node.id]);
      expect(store.selectedNodeId, node.id);
      expect(store.settings.mixedPort, '17932');
      expect(store.subs, isEmpty);
      expect(store.traffic.up, 0);
      expect(store.hist['down'], everyElement(0));
      expect((await controller.store.loadProfile()).nodes.single.id, node.id);
      expect(host.operations, ['capabilities', 'status']);
    },
  );

  test(
    'power delegates start/stop and reflects native failure and rollback',
    () async {
      await store.toggleRunning();
      expect(store.running, isTrue);
      host.failApply = true;
      store.setSettings((s) => s.copyWith(mode: FlvpProxyMode.global));
      await store.flushSettings();
      expect(store.settings.mode, FlvpProxyMode.rule);
      expect(store.toast!.message, contains('已恢复上一配置'));
      expect(store.running, isTrue);
      await store.toggleRunning();
      expect(store.running, isFalse);
    },
  );

  test(
    'mode and node apply persist while appearance never restarts native core',
    () async {
      await store.toggleRunning();
      final operationCount = host.operations.length;
      store.toggleTheme();
      await store.flushSettings();
      expect(host.operations.length, operationCount);
      store.setSettings((s) => s.copyWith(mode: FlvpProxyMode.global));
      await store.selectNode(directTarget);
      expect(controller.profile.mode, RoutingMode.global);
      expect(controller.selectedNodeId, directTarget);
      expect(store.selectedNodeId, directTarget);
      expect((await controller.store.loadProfile()).mode, RoutingMode.global);
    },
  );

  test(
    'debounced fields apply only full valid port and preserve existing nodes',
    () async {
      store.setSettings((s) => s.copyWith(mixedPort: '1'));
      store.setSettings((s) => s.copyWith(mixedPort: '17934'));
      await store.flushSettings();
      expect(controller.mixedPort, 17934);
      expect(controller.profile.nodes.single.id, node.id);
      store.setSettings((s) => s.copyWith(mixedPort: '70000'));
      await store.flushSettings();
      expect(store.settings.mixedPort, '17934');
      expect(controller.mixedPort, 17934);
      expect(store.toast!.message, contains('1024–65535'));
    },
  );

  test(
    'unsupported operations never fake success or mutate settings',
    () async {
      store.setSettings((s) => s.copyWith(systemProxy: true));
      expect(store.settings.systemProxy, isFalse);
      store.setSettings((s) => s.copyWith(tunMode: true));
      expect(store.settings.tunMode, isFalse);
      expect(store.subs, isEmpty);
      expect(store.toast!.message, contains('尚未实现'));
      expect(host.operations, ['capabilities', 'status']);
    },
  );

  test(
    'system proxy requires a running listener and follows native state',
    () async {
      host.supportsSystemProxy = true;
      // Capabilities were loaded during setup; initialize a fresh controller to
      // exercise the Windows capability handshake.
      store.dispose();
      controller.dispose();
      controller = ClientController(
        store: controller.store,
        bridge: CoreBridge(host),
      );
      store = FlvpClientStore(controller);
      await store.initializeClient();

      store.setSettings((s) => s.copyWith(systemProxy: true));
      expect(store.settings.systemProxy, isFalse);
      expect(store.toast!.message, contains('先启动'));

      await store.toggleRunning();
      store.setSettings((s) => s.copyWith(systemProxy: true));
      await store.flushSettings();
      expect(host.operations.last, 'enableSystemProxy');
      expect(store.settings.systemProxy, isTrue);

      store.setSettings((s) => s.copyWith(systemProxy: false));
      await store.flushSettings();
      expect(host.operations.last, 'disableSystemProxy');
      expect(store.settings.systemProxy, isFalse);
      host.failSystemProxy = true;
      store.setSettings((s) => s.copyWith(systemProxy: true));
      await store.flushSettings();
      expect(store.settings.systemProxy, isFalse);
      expect(store.toast!.message, contains('test WinINet failure'));
    },
  );

  test('second power press cancels in-flight native start', () async {
    host.startGate = Completer<void>();
    host.startEntered = Completer<void>();
    final starting = store.toggleRunning();
    await host.startEntered!.future;
    final stopping = store.toggleRunning();
    host.startGate!.complete();
    await Future.wait([starting, stopping]);
    expect(store.running, isFalse);
    expect(host.operations.last, 'stop');
    expect(await controller.store.hasPending(), isFalse);
  });

  test('later settings draft survives an in-flight node switch', () async {
    await store.toggleRunning();
    host.applyGate = Completer<void>();
    host.applyEntered = Completer<void>();
    final switching = store.selectNode(directTarget);
    await host.applyEntered!.future;
    store.setSettings((s) => s.copyWith(mode: FlvpProxyMode.global));
    host.applyGate!.complete();
    await switching;
    expect(store.settings.mode, FlvpProxyMode.global);
    await store.flushSettings();
    expect(controller.profile.mode, RoutingMode.global);
    expect(controller.selectedNodeId, directTarget);
  });

  test(
    'dispose during native response leaves Android runtime running',
    () async {
      host.startGate = Completer<void>();
      host.startEntered = Completer<void>();
      final starting = store.toggleRunning();
      await host.startEntered!.future;
      store.dispose();
      host.startGate!.complete();
      await starting;
      expect(controller.status.running, isTrue);
      // TearDown still owns disposal; replace the already disposed adapter.
      store = FlvpClientStore(controller);
    },
  );
}
