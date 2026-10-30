import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';

const nodeId = '97bf1420-1849-4963-96c8-d836aa75a5c5';
const ruleId = '77bf1420-1849-4963-96c8-d836aa75a5c5';
const node = ProxyNode(
  id: nodeId,
  displayName: '测试节点',
  protocol: NodeProtocol.socks5,
  server: '127.0.0.1',
  port: 1080,
);
const compiler = ConfigCompiler();

void main() {
  test('canonical JSON sorts every nested object', () {
    expect(
      canonicalJson({
        'z': [
          {'b': 2, 'a': 1},
        ],
        'a': true,
      }),
      '{"a":true,"z":[{"a":1,"b":2}]}',
    );
  });
  test('compilation deterministic; local port changes only runtime hash', () {
    final profile = Profile.initial();
    final a = compiler.compile(profile, mixedPort: 17890);
    final b = compiler.compile(
      Profile.fromText(jsonEncode(profile.toJson())),
      mixedPort: 17890,
    );
    final c = compiler.compile(profile, mixedPort: 17891);
    expect(a.text, b.text);
    expect(a.runtimeHash, b.runtimeHash);
    expect(a.logicalHash, c.logicalHash);
    expect(a.runtimeHash, isNot(c.runtimeHash));
    expect(jsonDecode(a.text)['rules'], ['MATCH,DIRECT']);
  });
  test(
    'mode semantics compile explicit final MATCH and stable UUID references',
    () {
      final profile = Profile.initial().copyWith(
        nodes: [node],
        rules: [
          const RuleSpec(
            id: ruleId,
            kind: RuleKind.domainSuffix,
            value: 'example.org',
            targetId: nodeId,
          ),
        ],
        finalTargetId: proxyTarget,
      );
      final compiled = jsonDecode(
        compiler
            .compile(profile, mixedPort: 17890, selectedNodeId: nodeId)
            .text,
      );
      expect(compiled['rules'], [
        'DOMAIN-SUFFIX,example.org,${node.coreName}',
        'MATCH,PROXY',
      ]);
      expect(compiled['proxy-groups'][0]['proxies'][0], node.coreName);
      for (final mode in [RoutingMode.direct, RoutingMode.global]) {
        final json = jsonDecode(
          compiler.compile(profile.copyWith(mode: mode), mixedPort: 17890).text,
        );
        expect(json['rules'], [
          mode == RoutingMode.direct ? 'MATCH,DIRECT' : 'MATCH,PROXY',
        ]);
      }
    },
  );
  test('strict import rejects unknown fields, unsupported protocols and overflowing ports', () {
    final profile = Profile.initial().toJson();
    expect(
      () => Profile.fromJson({...profile, 'providers': []}),
      throwsA(isA<ConfigurationException>()),
    );
    final rawNode = node.toJson();
    expect(
      () => ProxyNode.fromJson({...rawNode, 'protocol': 'vmess'}),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => ProxyNode.fromJson({...rawNode, 'port': 65536}),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => compiler.compile(Profile.initial(), mixedPort: 65536),
      throwsA(isA<ConfigurationException>()),
    );
  });
  test('dangling references, duplicate IDs, invalid rules cannot compile', () {
    expect(
      () => compiler.compile(
        Profile.initial().copyWith(finalTargetId: nodeId),
        mixedPort: 17890,
      ),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => compiler.compile(
        Profile.initial().copyWith(nodes: [node, node]),
        mixedPort: 17890,
      ),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => const RuleSpec(
        id: ruleId,
        kind: RuleKind.ipCidr,
        value: '10.0.0.1/33',
        targetId: directTarget,
      ).validate(),
      throwsA(isA<ConfigurationException>()),
    );
    expect(
      () => const RuleSpec(
        id: ruleId,
        kind: RuleKind.network,
        value: 'QUIC',
        targetId: directTarget,
      ).validate(),
      throwsA(isA<ConfigurationException>()),
    );
  });
  test('node rename preserves compiled rule target', () {
    final renamed = ProxyNode(
      id: node.id,
      displayName: '另一个名字',
      protocol: node.protocol,
      server: node.server,
      port: node.port,
    );
    expect(renamed.coreName, node.coreName);
  });

  group('snapshot store', () {
    late Directory root;
    late SnapshotStore store;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('flvp-store-');
      store = SnapshotStore(root);
      await store.initialize();
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });
    test(
      'atomic replacement persists profile and local settings together',
      () async {
        await store.saveClientState(Profile.initial(), 17890, null);
        final changed = Profile.initial().copyWith(displayName: '持久化');
        await store.saveClientState(changed, 17891, directTarget);
        expect((await store.loadProfile()).displayName, '持久化');
        expect((await store.loadDeviceSettings())['mixedPort'], 17891);
      },
    );
    test(
      'staged snapshots are immutable and commit recovers the candidate',
      () async {
        final first = Profile.initial();
        final a = await store.stage(
          compiler.compile(first, mixedPort: 17890),
          profile: first,
          selectedNodeId: null,
        );
        final changed = first.copyWith(displayName: '恢复的配置');
        final b = await store.stage(
          compiler.compile(changed, mixedPort: 17891),
          profile: changed,
          selectedNodeId: directTarget,
        );
        expect(b.revision, a.revision + 1);
        await store.beginApply(b, a.revision);
        expect(await store.hasPending(), isTrue);
        await store.commit(b.revision, b.config.runtimeHash);
        expect(await store.hasPending(), isFalse);
        expect((await store.loadProfile()).displayName, '恢复的配置');
        expect(
          await File('${root.path}/runtime/${a.revision}/config.json')
              .readAsString(),
          a.config.text,
        );
      },
    );
    test('tampered snapshot cannot publish an applied pointer', () async {
      final profile = Profile.initial();
      final snapshot = await store.stage(
        compiler.compile(profile, mixedPort: 17890),
        profile: profile,
        selectedNodeId: null,
      );
      await store.beginApply(snapshot, 0);
      await File('${root.path}/runtime/${snapshot.revision}/config.json')
          .writeAsString('{}');
      await expectLater(
        store.commit(snapshot.revision, snapshot.config.runtimeHash),
        throwsA(isA<ConfigurationException>()),
      );
      expect(await File('${root.path}/state/applied.json').exists(), isFalse);
      expect(await store.hasPending(), isTrue);
    });
    test(
      'tampered metadata cannot disagree with compiled runtime bytes',
      () async {
        final profile = Profile.initial();
        final snapshot = await store.stage(
          compiler.compile(profile, mixedPort: 17890),
          profile: profile,
          selectedNodeId: null,
        );
        final file = File(
          '${root.path}/runtime/${snapshot.revision}/snapshot.json',
        );
        final metadata =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        metadata['client']['device']['mixedPort'] = 17891;
        await file.writeAsString(jsonEncode(metadata));
        await expectLater(
          store.commit(snapshot.revision, snapshot.config.runtimeHash),
          throwsA(isA<ConfigurationException>()),
        );
        expect(await File('${root.path}/state/applied.json').exists(), isFalse);
      },
    );
  });
}
