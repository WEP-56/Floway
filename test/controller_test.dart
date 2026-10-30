import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';

import 'fake_host.dart';

class FailingCommitStore extends SnapshotStore {
  FailingCommitStore(super.root);
  bool failNextCommit = false;
  @override
  Future<void> commit(int revision, String hash) async {
    if (failNextCommit) {
      failNextCommit = false;
      throw const FileSystemException('injected disk failure');
    }
    await super.commit(revision, hash);
  }
}

void main() {
  late Directory root;
  late FakeHost host;
  late ClientController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flvp-controller-');
    host = FakeHost();
    c = ClientController(store: SnapshotStore(root), bridge: CoreBridge(host));
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  test('disk failure after activation keeps actual settings and recoverable journal', () async {
    await c.connect();
    c.dispose();
    final store = FailingCommitStore(root);
    c = ClientController(store: store, bridge: CoreBridge(host));
    await c.initialize();
    store.failNextCommit = true;
    await c.save(c.profile.copyWith(displayName: '磁盘恢复'), port: 17901);
    expect(c.error, contains('injected disk failure'));
    expect(c.status.running, isTrue);
    expect(c.profile.displayName, '磁盘恢复');
    expect(c.status.mixedPort, 17901);
    expect(await store.hasPending(), isTrue);
    c.dispose();
    c = ClientController(store: SnapshotStore(root), bridge: CoreBridge(host));
    await c.initialize();
    expect(c.error, isNull);
    expect(c.profile.displayName, '磁盘恢复');
    expect(c.mixedPort, 17901);
    expect(await c.store.hasPending(), isFalse);
  });
  test(
    'removing selected unreferenced node resets the selection explicitly',
    () async {
      const node = ProxyNode(
        id: '97bf1420-1849-4963-96c8-d836aa75a5c5',
        displayName: '临时节点',
        protocol: NodeProtocol.http,
        server: '127.0.0.1',
        port: 8080,
      );
      await c.save(c.profile.copyWith(nodes: [node]), selection: node.id);
      await c.save(c.profile.copyWith(nodes: []));
      expect(c.error, isNull);
      expect(c.selectedNodeId, directTarget);
    },
  );
  test('stop during native start wins after start completion', () async {
    host.startGate = Completer<void>();
    host.startEntered = Completer<void>();
    final starting = c.connect();
    await host.startEntered!.future;
    final stopping = c.stop();
    host.startGate!.complete();
    await Future.wait([starting, stopping]);
    expect(c.status.running, isFalse);
    expect(host.operations.last, 'stop');
    expect(await c.store.hasPending(), isFalse);
  });
  test('immediate start then stop does not start a listener', () async {
    await Future.wait([c.connect(), c.stop()]);
    expect(host.operations, isNot(contains('start')));
    expect(c.status.running, isFalse);
  });
  test('failed apply retains previous desired and applied state', () async {
    await c.connect();
    final previous = c.status.appliedRevision;
    host.failApply = true;
    await c.save(c.profile.copyWith(displayName: '不能应用'), port: 17891);
    expect(c.status.running, isTrue);
    expect(c.status.appliedRevision, previous);
    expect(c.profile.displayName, '本地直连测试');
    expect(c.mixedPort, 17890);
    expect(c.error, contains('已恢复上一配置'));
    expect((await c.store.loadProfile()).displayName, '本地直连测试');
    expect(await c.store.hasPending(), isFalse);
  });
  test('successful apply commits profile and device state', () async {
    await c.connect();
    await c.save(c.profile.copyWith(displayName: '新配置'), port: 17892);
    expect(c.error, isNull);
    expect(c.status.mixedPort, 17892);
    expect((await c.store.loadProfile()).displayName, '新配置');
    expect((await c.store.loadDeviceSettings())['mixedPort'], 17892);
  });
  test(
    'reattachment recovers pending running snapshot and desired settings',
    () async {
      final profile = c.profile.copyWith(displayName: 'Activity 恢复');
      final snapshot = await c.store.stage(
        const ConfigCompiler().compile(profile, mixedPort: 17893),
        profile: profile,
        selectedNodeId: directTarget,
      );
      await c.store.beginApply(snapshot, 0);
      await c.bridge.start(snapshot);
      c.dispose();
      c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(host),
      );
      await c.initialize();
      expect(c.error, isNull);
      expect(c.profile.displayName, 'Activity 恢复');
      expect(c.mixedPort, 17893);
      expect(c.status.running, isTrue);
      expect(await c.store.hasPending(), isFalse);
    },
  );
  test(
    'reattachment after process death clears pending without reconnecting',
    () async {
      final snapshot = await c.store.stage(
        c.compiler.compile(c.profile, mixedPort: 17890),
        profile: c.profile,
        selectedNodeId: null,
      );
      await c.store.beginApply(snapshot, 0);
      c.dispose();
      c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(FakeHost()),
      );
      await c.initialize();
      expect(c.status.running, isFalse);
      expect(await c.store.hasPending(), isFalse);
    },
  );
}
