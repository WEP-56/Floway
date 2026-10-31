import 'dart:convert';

import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = ConfigurationImporter();

  test('真实订阅的 TLS 指纹、ws 早期数据、非 ASCII sni 只降级字段', () {
    const text = '''
proxies:
  - name: fp
    type: vless
    server: a.example.test
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    tls: true
    servername: a.example.test
    client-fingerprint: chrome
    network: ws
    ws-opts:
      path: /p
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
  - name: sn
    type: trojan
    server: b.example.test
    port: 443
    password: pw
    sni: 例子.中国
  - name: sk
    type: socks5
    server: c.example.test
    port: 1080
    username: "null"
    password: "null"
rules:
  - MATCH,DIRECT
''';
    final warnings = <String>[];
    final profile = importer.parse(text, name: 'tolerant', warnings: warnings);
    expect(profile.nodes.length, 3);
    expect(warnings.any((w) => w.contains('client-fingerprint')), isTrue);
    expect(warnings.any((w) => w.contains('max-early-data')), isTrue);
    expect(warnings.any((w) => w.contains('sni')), isTrue);
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
    );
    expect(compiled.text, contains('MATCH,DIRECT'));
  });

  test('密码型协议不受用户名成对校验影响', () {
    const text = '''
proxies:
  - name: hy
    type: hysteria2
    server: d.example.test
    port: 443
    password: pw
    sni: d.example.test
  - name: ss
    type: ss
    server: e.example.test
    port: 8388
    cipher: aes-128-gcm
    password: pw
rules:
  - MATCH,DIRECT
''';
    final warnings = <String>[];
    final profile = importer.parse(text, name: 'pw', warnings: warnings);
    expect(profile.nodes.length, 2);
    expect(warnings.where((w) => w.contains('认证信息')), isEmpty);
  });

  test('编译输出仍是可解析 JSON', () {
    final profile = importer.parse(
      jsonEncode({
        'proxies': [
          {
            'name': 'a',
            'type': 'http',
            'server': 'a.example.test',
            'port': 8080,
          },
        ],
      }),
      name: 'json',
    );
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
    );
    expect(jsonDecode(compiled.text), isA<Map<String, dynamic>>());
  });
}
