import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';

Map<String, dynamic> policyDocument() => {
  'mixed-port': 9999,
  'allow-lan': true,
  'bind-address': '*',
  'external-controller': '0.0.0.0:9090',
  'proxies': [
    {'name': 'A', 'type': 'http', 'server': 'a.test', 'port': 8080},
    {'name': 'B', 'type': 'socks5', 'server': 'b.test', 'port': 1080},
  ],
  'proxy-groups': [
    {
      'name': 'Main',
      'type': 'select',
      'proxies': ['Backup', 'A', 'DIRECT'],
    },
    {
      'name': 'Backup',
      'type': 'fallback',
      'proxies': ['A', 'B'],
      'url': 'https://example.test/check',
      'interval': 60,
      'lazy': false,
    },
    {
      'name': 'Fast',
      'type': 'url-test',
      'proxies': ['A', 'B'],
      'url': 'http://example.test/check',
      'interval': 300,
      'tolerance': 50,
      'lazy': false,
    },
  ],
  'rules': [
    'DOMAIN-SUFFIX,example.test,Main',
    'IP-CIDR6,2001:db8::/32,DIRECT,no-resolve',
    'MATCH,Fast',
  ],
};

void main() {
  const importer = ConfigurationImporter();
  Profile parse(Map<String, dynamic> doc, {List<String>? warnings}) =>
      importer.parse(jsonEncode(doc), name: 'Policy', warnings: warnings);
  test('Clash policies preserve references, order and local ownership', () {
    final profile = parse(policyDocument());
    expect(profile.groups.length, 3);
    expect(profile.rules[0].targetId, profile.groups[0].id);
    expect(profile.finalTargetId, profile.groups[2].id);
    final restored = Profile.fromText(jsonEncode(profile.toJson()));
    final compiled = const ConfigCompiler().compile(
      restored,
      mixedPort: 17890,
      selectedNodeId: profile.nodes[1].id,
    );
    final config = jsonDecode(compiled.text);
    expect(config['mixed-port'], 17890);
    expect(config['allow-lan'], false);
    expect(config.containsKey('external-controller'), false);
    expect(config['proxy-groups'][1]['proxies'][0], profile.groups[1].coreName);
    expect(
      config['rules'][0],
      'DOMAIN-SUFFIX,example.test,${profile.groups[0].coreName}',
    );
    expect(config['rules'][1], 'IP-CIDR,2001:db8::/32,DIRECT,no-resolve');
    final global = jsonDecode(
      const ConfigCompiler()
          .compile(profile.copyWith(mode: RoutingMode.global), mixedPort: 17890)
          .text,
    );
    expect(global['rules'], ['MATCH,PROXY']);
    expect(global['proxy-groups'].length, 1);
    final direct = jsonDecode(
      const ConfigCompiler()
          .compile(profile.copyWith(mode: RoutingMode.direct), mixedPort: 17890)
          .text,
    );
    expect(direct['rules'], ['MATCH,DIRECT']);
    expect(direct['proxy-groups'].length, 1);
  });
  test('group selections persist, survive reorder, and missing selection rejects refresh', () {
    var profile = parse(policyDocument());
    profile = profile.copyWith(
      groups: [
        profile.groups[0].select(profile.nodes[0].id),
        ...profile.groups.skip(1),
      ],
    );
    final source = ConfigurationSource(
      id: profile.id,
      name: 'Policy',
      kind: ConfigurationSourceKind.remote,
      original: '',
      profile: profile,
      selectedNodeId: directTarget,
      updatedAt: DateTime.utc(2026),
      url: 'https://example.test/sub',
    );
    final updated = policyDocument();
    (updated['proxies'] as List)[0]['name'] = 'renamed A';
    for (final group in updated['proxy-groups'] as List) {
      group['proxies'] = (group['proxies'] as List)
          .map((n) => n == 'A' ? 'renamed A' : n)
          .toList()
          .reversed
          .toList();
    }
    final result = importer.reconcile(parse(updated), source);
    expect(result.groups[0].id, profile.groups[0].id);
    expect(result.groups[0].selectedId, profile.nodes[0].id);
    expect(result.rules[0].targetId, result.groups[0].id);
    (updated['proxy-groups'] as List)[0]['proxies'] = ['DIRECT'];
    expect(
      () => importer.reconcile(parse(updated), source),
      throwsA(isA<ConfigurationException>()),
    );
  });
  test('结构性错误仍然整体失败', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) => d['rules'] = ['MATCH,Main', 'DOMAIN,a.test,A'],
      (d) => d['rules'] = ['RULE-SET,ads,DIRECT', 'MATCH,Main'],
      (d) => d['rules'] = ['IP-CIDR6,127.0.0.1/32,DIRECT', 'MATCH,Main'],
      (d) => d['rules'] = ['DOMAIN,a.test,DIRECT,no-resolve', 'MATCH,Main'],
      (d) => d.remove('rules'),
    ];
    for (final mutate in mutations) {
      final d = policyDocument();
      mutate(d);
      expect(() => parse(d), throwsA(isA<ConfigurationException>()));
    }
  });

  test('未支持的策略组语义只降级自身并给出字段级警告', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) => d['proxy-groups'][0]['proxies'] = ['Missing'],
      (d) => d['proxy-groups'][0]['proxies'] = ['A', 'A'],
      (d) => d['proxy-groups'][0]['name'] = 'A',
      (d) => d['proxy-groups'][1]['lazy'] = true,
      (d) => d['proxy-groups'][1]['interval'] = 1,
      (d) => d['proxy-groups'][1]['url'] = 'file:///local',
      (d) => d['proxy-groups'][1]['disable-udp'] = true,
      (d) => d['proxy-groups'][1]['type'] = 'load-balance',
      (d) => d['rules'] = ['DOMAIN,a.test,A'],
      (d) => d['dns'] = {'enable': true},
    ];
    for (final mutate in mutations) {
      final d = policyDocument();
      mutate(d);
      final warnings = <String>[];
      final profile = parse(d, warnings: warnings);
      expect(profile.nodes, isNotEmpty);
    }
  });
}
