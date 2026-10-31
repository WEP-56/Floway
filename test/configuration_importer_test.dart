import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';

void main() {
  const importer = ConfigurationImporter();
  test(
    'real YAML and URI fixtures compile with an explicit proxy default',
    () async {
      for (final file in ['clash-nodes.yaml', 'nodes.txt']) {
        final text = await File('test/fixtures/subscriptions/$file')
            .readAsString();
        final profile = importer.parse(text, name: '测试');
        expect(profile.nodes.length, 2);
        expect(profile.finalTargetId, proxyTarget);
        final compiled = const ConfigCompiler().compile(
          profile,
          mixedPort: 17890,
          selectedNodeId: profile.nodes.first.id,
        );
        expect(jsonDecode(compiled.text)['rules'], ['MATCH,PROXY']);
      }
    },
  );
  test('Base64 lists, IPv6 and manual node retain protocol and address', () {
    final profile = importer.parse(
      base64Encode(utf8.encode('socks5://[::1]:1080#Local')),
      name: 'IPv6',
    );
    expect(profile.nodes.single.server, '::1');
    expect(profile.nodes.single.protocol, NodeProtocol.socks5);
    expect(
      importer
          .manual('Manual', NodeProtocol.http, 'example.test', 8080)
          .finalTargetId,
      proxyTarget,
    );
  });
  test('native full profile preserves rules, mode and final target', () {
    final profile = Profile.initial().copyWith(
      rules: [
        const RuleSpec(
          id: '11111111-1111-4111-8111-111111111111',
          kind: RuleKind.domain,
          value: 'example.test',
          targetId: rejectTarget,
        ),
      ],
    );
    final parsed = importer.parse(jsonEncode(profile.toJson()), name: '完整配置');
    expect(parsed.toJson(), profile.toJson());
  });
  test(
    'unsupported full configurations never silently drop semantics',
    () async {
      for (final text in [
        'proxies: []\ndns: {enable: true}',
        '{"outbounds": [{"type":"direct"}]}',
        'ss://private-secret@example.test:443',
        'socks5://example.test',
        'x' * (maxImportBytes + 1),
      ]) {
        try {
          importer.parse(text, name: '拒绝');
          fail('must reject unsupported text');
        } on ConfigurationException catch (e) {
          expect(e.message, isNot(contains('private-secret')));
        }
      }
    },
  );
  test(
    '真实订阅风格里的未知字段逐项警告而不是整份失败',
    () async {
      const text = '''
mixed-port: 7890
mode: Rule
log-level: info
allow-lan: true
ipv6: false
tun:
  enable: true
proxy-providers:
  p: {type: http, url: 'https://example.test/p.yaml', path: ./p.yaml}
proxies:
  - {name: a, type: vmess, server: a.example.test, port: 443, uuid: 11111111-1111-1111-1111-111111111111, alterId: 0, cipher: auto, tls: true, servername: t.example.test, ws-opts: {path: /ws}}
  - {name: b, type: ss, server: b.example.test, port: 8388, cipher: aes-128-gcm, password: hidden, plugin: obfs, plugin-opts: {mode: tls}}
proxy-groups:
  - {name: PROXY, type: select, proxies: [a, b, DIRECT]}
  - {name: LB, type: load-balance, proxies: [a, b], url: 'https://example.test/204', interval: 300, strategy: round-robin}
rules:
  - RULE-SET,ads,REJECT
  - PROCESS-NAME,chrome.exe,PROXY
  - DOMAIN-SUFFIX,example.test,PROXY
  - MATCH,PROXY
rule-providers:
  ads: {type: http, behavior: domain, url: 'https://example.test/ads.txt', path: ./ads.txt}
''';
      final warnings = <String>[];
      final profile = importer.parse(text, name: '容忍', warnings: warnings);
      expect(profile.nodes, isNotEmpty);
      expect(warnings, isNotEmpty);
      for (final warning in warnings) {
        expect(warning, isNot(contains('private')));
      }
      final duplicated = importer.parse(
        'http://example.test:8080#same\nhttp://example.test:8080#same',
        name: '重复名称',
      );
      expect(duplicated.nodes.length, 2);
      expect(
        duplicated.nodes.map((node) => node.displayName).toSet().length,
        2,
      );
    },
  );
  test(
    'refresh matches endpoint identity not names; removed selection fails',
    () {
      final oldProfile = importer.parse(
        'http://a.test:8080#same\nsocks5://b.test:1080#same',
        name: 'old',
      );
      final source = ConfigurationSource(
        id: oldProfile.id,
        name: 'source',
        kind: ConfigurationSourceKind.remote,
        original: '',
        profile: oldProfile,
        selectedNodeId: oldProfile.nodes.first.id,
        updatedAt: DateTime.utc(2026),
        url: 'https://example.test/sub',
      );
      final parsed = importer.parse(
        'socks5://b.test:1080#renamed\nhttp://a.test:8080#renamed',
        name: 'new',
      );
      final result = importer.reconcile(parsed, source);
      expect(result.nodes.last.id, oldProfile.nodes.first.id);
      expect(result.nodes.first.id, oldProfile.nodes.last.id);
      expect(
        () => importer.reconcile(
          importer.parse('http://new.test:8080#same', name: 'new'),
          source,
        ),
        throwsA(isA<ConfigurationException>()),
      );
    },
  );
  test(
    'remote fetch validates status, redirects, size and hides URL tokens',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        switch (request.uri.path) {
          case '/ok':
            request.response.write('http://example.test:8080');
          case '/redirect':
            request.response.statusCode = 302;
            request.response.headers.set('location', '/ok');
          case '/large':
            request.response.write('x' * (maxImportBytes + 1));
          default:
            request.response.statusCode = 403;
        }
        await request.response.close();
      });
      try {
        const fetcher = SubscriptionFetcher();
        final base = 'http://127.0.0.1:${server.port}';
        expect(await fetcher.fetch('$base/ok'), contains('example.test'));
        for (final path in [
          '/redirect',
          '/large',
          '/denied?token=private-token',
        ]) {
          try {
            await fetcher.fetch('$base$path');
            fail('must reject');
          } on ConfigurationException catch (e) {
            expect(e.message, isNot(contains('private-token')));
          }
        }
      } finally {
        await server.close(force: true);
      }
    },
  );
}
