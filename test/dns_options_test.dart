import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';

Map<String, dynamic> dnsDocument() => {
  'proxies': [
    {'name': 'A', 'type': 'http', 'server': 'node.example.test', 'port': 8080},
  ],
  'dns': <String, dynamic>{
    'enable': true,
    'ipv6': false,
    'enhanced-mode': 'redir-host',
    'nameserver': [
      '223.5.5.5',
      'udp://127.0.0.1:5353',
      'tcp://1.1.1.1:53',
      'tls://1.1.1.1',
      'https://dns.example.test/dns-query',
    ],
    'fallback': ['127.0.0.1:5354'],
    'fallback-filter': <String, dynamic>{
      'geoip': false,
      'ipcidr': ['240.0.0.0/4', '2001:db8::/32'],
      'domain': ['+.example.test'],
    },
  },
};

void main() {
  const importer = ConfigurationImporter(), compiler = ConfigCompiler();
  Profile parse(Map<String, dynamic> d) =>
      importer.parse(jsonEncode(d), name: 'DNS test');
  test('custom DNS preserves typed fields through compilation, modes and persistence', () {
    final document = dnsDocument();
    final profile = parse(document);
    expect(profile.dns.toJson(), document['dns']);
    final persisted = Profile.fromText(jsonEncode(profile.toJson()));
    for (final mode in RoutingMode.values) {
      final compiled = compiler.compile(
        persisted.copyWith(mode: mode),
        mixedPort: 17890,
      );
      expect(jsonDecode(compiled.text)['dns'], profile.dns.toRuntimeJson());
      expect(jsonDecode(compiled.text)['tun']['enable'], false);
    }
    final legacy = Profile.initial().toJson()..remove('dns');
    expect(Profile.fromJson(legacy).dns.enabled, false);
    expect(parse({'proxies': document['proxies']}).dns.enabled, false);
  });
  test('DNS refresh is profile scoped and changes hashes without changing node identity', () {
    final profile = parse(dnsDocument());
    final source = ConfigurationSource(
      id: profile.id,
      name: 'DNS',
      kind: ConfigurationSourceKind.remote,
      original: '',
      profile: profile,
      selectedNodeId: profile.nodes.single.id,
      updatedAt: DateTime.utc(2026),
      url: 'https://example.test/sub',
    );
    final update = dnsDocument();
    update['dns']['nameserver'] = ['8.8.8.8'];
    final refreshed = importer.reconcile(parse(update), source);
    expect(refreshed.dns.nameservers, ['8.8.8.8']);
    expect(refreshed.nodes.single.id, profile.nodes.single.id);
    expect(
      compiler.compile(refreshed, mixedPort: 17890).runtimeHash,
      isNot(compiler.compile(profile, mixedPort: 17890).runtimeHash),
    );
    expect(
      profile.dns.nameservers,
      (dnsDocument()['dns'] as Map)['nameserver'],
    );
    expect(
      () => refreshed.dns.nameservers.add('1.1.1.1'),
      throwsUnsupportedError,
    );
  });
  test('resolver endpoints and unsupported semantics reject without echoing source', () {
    const secret = 'private-secret';
    for (final server in [
      'tls://dns.example.test',
      'https://dns.example.test#insecure',
      'https://dns.example.test?token=$secret',
      'udp://127.0.0.1/',
      'https://a..test/x',
      'UDP://1.1.1.1',
      '127.0.0.1:0',
      '127.0.0.1:65536',
      '127.0.0.1:',
      'quic://1.1.1.1',
      '[::1]:53',
      'https://u:$secret@a.test/x',
      'https://dns\\example.test/query',
      'https://%64ns.test/query',
      '1.1.1.1 bad',
    ]) {
      final d = dnsDocument();
      d['dns']['nameserver'] = [server];
      try {
        parse(d);
        fail('invalid synthetic DNS accepted: $server');
      } on ConfigurationException catch (e) {
        expect(e.message, isNot(contains(secret)));
      }
    }
    for (final change in <void Function(Map<String, dynamic>)>[
      (d) => d['enable'] = 'true',
      (d) => d['nameserver'] = [],
      (d) => d['nameserver'] = null,
      (d) => d['fallback'] = null,
      (d) => d['nameserver'] = List.filled(17, '1.1.1.1'),
      (d) => d['nameserver'] = ['1.1.1.1', '1.1.1.1'],
      (d) => d['ipv6'] = true,
      (d) => d['enable'] = false,
      (d) => d['enhanced-mode'] = 'fake-ip',
      (d) => d['listen'] = '127.0.0.1:53',
      (d) => d['respect-rules'] = false,
      (d) => d['default-nameserver'] = ['1.1.1.1'],
      (d) => d['nameserver-policy'] = {'+.example.test': '1.1.1.1'},
      (d) => d['fallback-filter']['geoip'] = true,
      (d) => d['fallback-filter'].remove('geoip'),
      (d) => d['fallback-filter']['ipcidr'] = ['1.1.1.1/33'],
      (d) => d['fallback-filter']['domain'] = ['exact.example.test'],
      (d) => d['fallback-filter']['domain'] = ['*.example.test'],
      (d) => d['fallback-filter']['geosite'] = ['cn'],
      (d) => d['fallback'] = [],
    ]) {
      final d = dnsDocument();
      change(d['dns'] as Map<String, dynamic>);
      expect(() => parse(d), throwsA(isA<ConfigurationException>()));
    }
  });
}
