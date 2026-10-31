import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';

const shareUuid = '11111111-1111-4111-8111-111111111111';
const shareKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  const importer = ConfigurationImporter();
  test('VLESS, Trojan and both Hysteria2 schemes import as typed nodes', () {
    final profile = importer.parse(
      [
        'vless://$shareUuid@v.example.test:443?security=reality&type=tcp&encryption=none&flow=xtls-rprx-vision&sni=tls.example.test&fp=chrome&pbk=$shareKey&sid=0123abcd#Reality',
        'vless://$shareUuid@ws.example.test:8443?security=tls&type=ws&sni=tls.example.test&host=ws.example.test&path=%2Fws%3Fed%3D0&alpn=h2%2Chttp%2F1.1#%E8%8A%82%E7%82%B9',
        'trojan://p%3Ass%2540@t.example.test:443?type=ws&path=%2F&host=ws.example.test&sni=tls.example.test&allowInsecure=0',
        'hysteria2://p%3Ass@h.example.test:443/?sni=tls.example.test&insecure=false',
        'hy2://other%40password@[2001:db8::1]:8443?insecure=1',
        'http://user:password@proxy.example.test:80',
      ].join('\r\n'),
      name: 'links',
    );
    expect(profile.nodes.length, 6);
    expect(profile.finalTargetId, proxyTarget);
    final restored = Profile.fromText(jsonEncode(profile.toJson()));
    final a = const ConfigCompiler().compile(profile, mixedPort: 17890);
    final b = const ConfigCompiler().compile(restored, mixedPort: 17890);
    expect(a.text, b.text);
    final nodes = jsonDecode(a.text)['proxies'] as List;
    expect(nodes[0]['reality-opts'], {
      'public-key': shareKey,
      'short-id': '0123abcd',
    });
    expect(nodes[0]['flow'], 'xtls-rprx-vision');
    expect(nodes[1]['ws-opts']['path'], '/ws?ed=0');
    expect(nodes[1]['ws-opts']['headers'], {'Host': 'ws.example.test'});
    expect(nodes[1]['alpn'], ['h2', 'http/1.1']);
    expect(profile.nodes[1].displayName, '节点');
    expect(nodes[2]['password'], 'p:ss%40');
    expect(nodes[2]['tls'], true);
    expect(nodes[3]['skip-cert-verify'], false);
    expect(nodes[4]['server'], '2001:db8::1');
    expect(nodes[4]['password'], 'other@password');
    expect(nodes[4]['skip-cert-verify'], true);
    expect(nodes[5]['port'], 80);
  });

  test('Base64 URL-safe and unpadded lists use the same semantics', () {
    const text =
        'vless://$shareUuid@v.example.test:80?encryption=none&type=tcp\n'
        'trojan://password@t.example.test:443\n'
        'hy2://password@h.example.test:443';
    final plain = importer.parse(text, name: 'plain');
    for (final encoded in [
      base64Encode(utf8.encode(text)),
      base64Url.encode(utf8.encode(text)).replaceAll('=', ''),
    ]) {
      final decoded = importer.parse(encoded, name: 'encoded');
      expect(
        decoded.nodes.map(ConfigurationImporter.identity),
        plain.nodes.map(ConfigurationImporter.identity),
      );
      expect(decoded.nodes.first.options.tls, false);
    }
  });

  test(
    'URI and Clash encodings share identity and stable refresh selection',
    () {
      final old = importer.parse(
        'hy2://p%3Ass@h.example.test:443?sni=tls.example.test#old',
        name: 'old',
      );
      final parsed = importer.parse(
        jsonEncode({
          'proxies': [
            {
              'name': 'new',
              'type': 'hysteria2',
              'server': 'h.example.test',
              'port': 443,
              'password': 'p:ss',
              'sni': 'tls.example.test',
            },
          ],
        }),
        name: 'new',
      );
      final source = ConfigurationSource(
        id: old.id,
        name: 'source',
        kind: ConfigurationSourceKind.remote,
        original: '',
        profile: old,
        selectedNodeId: old.nodes.single.id,
        updatedAt: DateTime.utc(2026),
        url: 'https://example.test/sub',
      );
      final refreshed = importer.reconcile(parsed, source);
      expect(refreshed.nodes.single.id, old.nodes.single.id);
      expect(refreshed.nodes.single.displayName, 'new');
      final changed = importer.parse(
        'hy2://changed@h.example.test:443?sni=tls.example.test',
        name: 'changed',
      );
      expect(
        () => importer.reconcile(changed, source),
        throwsA(isA<ConfigurationException>()),
      );
    },
  );

  test('unsupported or ambiguous semantics reject the whole list without secrets', () {
    const secret = 'private-secret';
    for (final link in [
      'vless://$secret@v.example.test:443',
      'vless://$shareUuid@v.example.test:443?security=tls&fp=chrome',
      'vless://$shareUuid@v.example.test:443?security=reality&pbk=$shareKey&fp=ios',
      'vless://$shareUuid@v.example.test:443?security=reality',
      'vless://$shareUuid@v.example.test:443?pbk=$shareKey',
      'vless://$shareUuid@v.example.test:443?encryption=aes',
      'vless://$shareUuid@v.example.test:443?type=grpc&serviceName=$secret',
      'vless://$shareUuid@v.example.test:443?type=tcp&path=%2F',
      'vless://$shareUuid@v.example.test:443?type=tcp&headerType=http',
      'vless://$shareUuid@v.example.test:443?security=tls&security=none',
      'vless://$shareUuid@v.example.test:443?security=reality&pbk=$shareKey&spx=%2F',
      'trojan://$secret@t.example.test:443?sni=a.test&sni=b.test',
      'trojan://$secret@t.example.test:443?insecure=1&allowInsecure=0',
      'trojan://$secret@t.example.test:443?insecure=yes',
      'trojan://$secret@t.example.test:443?security=none&sni=t.test',
      'trojan://$secret@t.example.test:443?type=ws&path=%0A',
      'trojan://$secret@t.example.test:443?type=ws&host=',
      'trojan://$secret@t.example.test:443?security=reality&pbk=$shareKey',
      'trojan://$secret@t.example.test',
      'trojan://$secret@t.example.test:0',
      'trojan://$secret@t.example.test:65536',
      'trojan://$secret@t.example.test:443/ignored',
      'trojan://$secret@t.example.test:443?bad=$secret',
      'trojan://$secret%0A@t.example.test:443',
      'trojan://$secret@t.example.test:443?type=t\tcp',
      'hy2://$secret@h.example.test:443?mport=443-8443',
      'hy2://$secret@h.example.test:443?obfs=salamander&obfs-password=$secret',
      'hy2://$secret@h.example.test:443?alpn=h3',
      'hy2://@h.example.test:443',
      'hy2://$secret@h.example.test:443?insecure=%XX',
      'vmess://$secret',
    ]) {
      try {
        importer.parse('http://proxy.example.test:80\n$link', name: 'reject');
        fail('unsupported input accepted');
      } on ConfigurationException catch (e) {
        expect(e.message, startsWith('第 2 行：'));
        expect(e.message, isNot(contains(secret)));
        expect(e.message, isNot(contains('example.test')));
      }
    }
  });
}
