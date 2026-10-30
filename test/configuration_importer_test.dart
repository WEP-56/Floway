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
        await File('test/fixtures/subscriptions/unsupported-full.yaml')
            .readAsString(),
        'proxies: []\ndns: {enable: true}',
        '{"outbounds": [{"type":"direct"}]}',
        'proxies:\n - {name: x, type: http, server: x.test, port: 8080, username: hidden}',
        'ss://private-secret@example.test:443',
        'http://example.test:8080?tls=true',
        'socks5://example.test',
        'http://example.test:8080\nhttp://example.test:8080',
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
