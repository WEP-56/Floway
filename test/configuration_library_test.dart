import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/ui/store/client_store.dart';

import 'fake_host.dart';

class FailPublish extends SnapshotStore {
  FailPublish(super.root);
  bool fail = false;
  @override
  Future<void> commit(int revision, String hash) async {
    if (fail) {
      fail = false;
      throw const FileSystemException('publish failure');
    }
    await super.commit(revision, hash);
  }
}

void main() {
  late Directory root;
  late FakeHost host;
  late ClientController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flvp-library-');
    host = FakeHost();
    c = ClientController(store: SnapshotStore(root), bridge: CoreBridge(host));
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  Future<void> import(String name, String text) =>
      c.importConfiguration(name, ConfigurationSourceKind.file, text: text);

  test(
    'sources persist snapshots, active scope and independent selections',
    () async {
      await import('A', 'http://a.test:8080\nsocks5://b.test:1080');
      final a = c.library.active!;
      await c.save(c.profile, selection: c.profile.nodes.last.id);
      final aSelection = c.selectedNodeId;
      await import('B', 'http://c.test:8080');
      final b = c.library.sources.last;
      await c.activateConfiguration(b.id);
      expect(c.profile.nodes.single.server, 'c.test');
      expect(c.selectedNodeId, b.profile.nodes.single.id);
      await c.activateConfiguration(a.id);
      expect(c.selectedNodeId, aSelection);
      expect((await c.store.loadLibrary()).active!.selectedNodeId, aSelection);
      expect(
        (await c.store.loadLibrary()).source(a.id).original,
        contains('http://a.test'),
      );
      final store = FlvpClientStore(c);
      await store.initializeClient();
      expect(store.nodes.map((n) => n.id), [
        directTarget,
        ...c.profile.nodes.map((n) => n.id),
      ]);
      expect(store.subs.length, 2);
      expect(store.subs.every((s) => !s.hasQuota && !s.remote), isTrue);
      store.dispose();
    },
  );
  test(
    'failed running switch keeps source and newly imported inactive entries',
    () async {
      await import('A', 'http://a.test:8080');
      final a = c.library.activeId;
      await c.connect();
      await import('B', 'socks5://b.test:1080');
      final b = c.library.sources.last.id;
      host.failApply = true;
      await c.activateConfiguration(b);
      expect(c.error, contains('APPLY_FAILED'));
      expect(c.library.activeId, a);
      expect(c.library.sources.length, 2);
      expect((await c.store.loadLibrary()).sources.length, 2);
      expect((await c.store.loadLibrary()).activeId, a);
    },
  );
  test('invalid import and active removal leave library untouched', () async {
    await import('A', 'http://a.test:8080');
    final before = canonicalJson(c.library.toJson());
    await import('invalid', 'vmess://not-supported');
    expect(c.error, isNotNull);
    expect(canonicalJson(c.library.toJson()), before);
    await c.removeConfiguration(c.library.activeId!);
    expect(c.error, contains('先切换'));
    expect(canonicalJson(c.library.toJson()), before);
    await import('B', 'http://b.test:8080');
    await c.removeConfiguration(c.library.sources.last.id);
    expect(c.library.sources.length, 1);
  });
  test(
    'successful running switch with publication failure recovers whole library',
    () async {
      await import('A', 'http://a.test:8080');
      await import('B', 'http://b.test:8080');
      final b = c.library.sources.last.id;
      await c.connect();
      c.dispose();
      final disk = FailPublish(root);
      c = ClientController(store: disk, bridge: CoreBridge(host));
      await c.initialize();
      disk.fail = true;
      await c.activateConfiguration(b);
      expect(c.error, contains('publish failure'));
      expect(c.library.activeId, b);
      expect(await disk.hasPending(), isTrue);
      c.dispose();
      c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(host),
      );
      await c.initialize();
      expect(c.library.activeId, b);
      expect(c.profile.nodes.single.server, 'b.test');
      expect(await c.store.hasPending(), isFalse);
    },
  );
  test('remote refresh preserves selection and keeps last valid version on removal', () async {
    var body = 'http://a.test:8080#one\nsocks5://b.test:1080#two';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write(body);
      await request.response.close();
    });
    try {
      await c.importConfiguration(
        'remote',
        ConfigurationSourceKind.remote,
        url: 'http://127.0.0.1:${server.port}/subscription?token=private',
      );
      expect(c.error, isNull);
      final id = c.library.activeId!;
      final selected = c.selectedNodeId;
      body = 'socks5://b.test:1080#renamed\nhttp://a.test:8080#renamed';
      await c.refreshConfiguration(id);
      expect(c.error, isNull);
      expect(c.selectedNodeId, selected);
      final before = canonicalJson(c.library.toJson());
      body = 'socks5://b.test:1080#two';
      await c.refreshConfiguration(id);
      expect(c.error, contains('移除了已选择节点'));
      expect(canonicalJson(c.library.toJson()), before);
      expect(canonicalJson((await c.store.loadLibrary()).toJson()), before);
    } finally {
      await server.close(force: true);
    }
  });
}
