import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';

void main() {
  const importer = ConfigurationImporter();
  test('all nine typed protocols survive persistence and deterministic compilation', () async {
    final text = await File('test/fixtures/subscriptions/advanced-nodes.json')
        .readAsString();
    final profile = importer.parse(text, name: 'Synthetic');
    expect(
      profile.nodes.map((n) => n.protocol).toSet(),
      NodeProtocol.values.toSet(),
    );
    final restored = Profile.fromText(jsonEncode(profile.toJson()));
    final a = const ConfigCompiler().compile(profile, mixedPort: 17890);
    final b = const ConfigCompiler().compile(restored, mixedPort: 17890);
    expect(a.text, b.text);
    final nodes = (jsonDecode(a.text)['proxies'] as List)
        .cast<Map<String, dynamic>>();
    expect(nodes.first['username'], 'sample-user');
    expect(nodes.first['tls'], isTrue);
    expect(
      nodes.firstWhere(
        (n) => n['type'] == 'vmess',
      )['ws-opts']['headers']['Host'],
      'ws.example.test',
    );
    expect(nodes.firstWhere((n) => n['type'] == 'hysteria')['up'], 11);
    expect(
      nodes.firstWhere((n) => n['type'] == 'vless')['reality-opts']['short-id'],
      '0123abcd',
    );
  });

  test('URI credentials are decoded once and auth affects identity, not display name', () {
    final old = importer.parse(
      'http://user:p%3Ass%2540@example.test:8080#old',
      name: 'auth',
    );
    expect(old.nodes.single.options.password, 'p:ss%40');
    final identity = ConfigurationImporter.identity(old.nodes.single);
    expect(identity, isNot(contains('user')));
    final source = ConfigurationSource(
      id: old.id,
      name: 'auth',
      kind: ConfigurationSourceKind.remote,
      original: '',
      profile: old,
      selectedNodeId: old.nodes.single.id,
      updatedAt: DateTime.utc(2026),
      url: 'https://example.test/sub',
    );
    final renamed = importer.parse(
      'http://user:p%3Ass%2540@example.test:8080#new',
      name: 'auth',
    );
    final merged = importer.reconcile(renamed, source);
    expect(merged.nodes.single.id, old.nodes.single.id);
    expect(
      merged.nodes.single.options.password,
      old.nodes.single.options.password,
    );
    final changed = importer.parse(
      'http://user:changed@example.test:8080',
      name: 'auth',
    );
    expect(
      ConfigurationImporter.identity(changed.nodes.single),
      isNot(identity),
    );
    expect(
      () => importer.reconcile(changed, source),
      throwsA(isA<ConfigurationException>()),
    );
    final separate = importer.parse(
      'http://u:p@example.test:80\nhttp://u:q@example.test:80',
      name: 'accounts',
    );
    expect(separate.nodes.length, 2);
  });

  test('protocol errors are explicit and do not include credentials', () {
    const uuid = '11111111-1111-4111-8111-111111111111';
    for (final parameters in <Map<String, Object?>>[
      {'type': 'http', 'username': 'private-secret'},
      {'type': 'socks5', 'username': 'u', 'password': 'x' * 256},
      {'type': 'http', 'username': 'u', 'password': 'private-secret\r\n'},
      {'type': 'http', 'tls': false, 'sni': 'example.test'},
      {'type': 'http', 'tls': 'true'},
      {'type': 'ss', 'password': 'private-secret', 'cipher': 'unsupported'},
      {'type': 'vmess', 'uuid': uuid, 'alterId': 1},
      {
        'type': 'vless',
        'uuid': uuid,
        'tls': true,
        'client-fingerprint': 'chrome',
      },
      {
        'type': 'vless',
        'uuid': uuid,
        'tls': true,
        'network': 'ws',
        'flow': 'xtls-rprx-vision',
      },
      {
        'type': 'vless',
        'uuid': uuid,
        'network': 'ws',
        'ws-opts': {'max-early-data': 2048},
      },
      {
        'type': 'vless',
        'uuid': uuid,
        'network': 'ws',
        'ws-opts': {
          'headers': {'Upgrade': 'not-websocket'},
        },
      },
      {
        'type': 'vless',
        'uuid': uuid,
        'tls': true,
        'sni': 'a.test',
        'servername': 'b.test',
      },
      {'type': 'hysteria2', 'password': 'private-secret', 'ports': '100-200'},
      {'type': 'hysteria2', 'password': 'private-secret', 'mport': '100-200'},
      {
        'type': 'hysteria',
        'auth-str': 'private-secret',
        'up': '1 Gbps',
        'down': 100,
      },
      {'type': 'trojan', 'password': null},
    ]) {
      try {
        importer.parse(
          jsonEncode({
            'proxies': [
              {
                'name': 'x',
                'server': 'example.test',
                'port': 443,
                ...parameters,
              },
            ],
          }),
          name: 'bad',
        );
        fail('must reject unsupported protocol options');
      } on ConfigurationException catch (e) {
        expect(e.message, isNot(contains('private-secret')));
      }
    }
  });
}
