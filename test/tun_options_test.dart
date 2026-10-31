import 'dart:convert';

import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/elevated_host.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = ConfigurationImporter();

  test('tun 字段按字段级降级，未支持字段单独提示', () {
    const text = '''
proxies:
  - {name: a, type: http, server: a.example.test, port: 8080}
tun:
  enable: true
  stack: mixed
  dns-hijack: [any:53]
  auto-route: true
  mtu: 1400
  mtu-future-key: 1
rules:
  - MATCH,DIRECT
''';
    final warnings = <String>[];
    final profile = importer.parse(text, name: 'tun', warnings: warnings);
    expect(profile.tun.enabled, isTrue);
    expect(profile.tun.autoRoute, isTrue);
    expect(profile.tun.mtu, 1400);
    expect(warnings.any((w) => w.contains('stack')), isTrue);
    expect(warnings.any((w) => w.contains('dns-hijack')), isTrue);
    expect(
      warnings.any((w) => w.contains('mtu-future-key') && w.contains('不受支持')),
      isTrue,
    );
  });

  test('编译输出携带 tun 运行时字段', () {
    final profile = importer.parse(
      jsonEncode({
        'proxies': [
          {'name': 'a', 'type': 'http', 'server': 'a.example.test', 'port': 8080},
        ],
        'tun': {'enable': true, 'auto-route': true},
      }),
      name: 'tun',
    );
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
    );
    final tun =
        (jsonDecode(compiled.text) as Map<String, dynamic>)['tun']
            as Map<String, dynamic>;
    expect(tun['enable'], isTrue);
    expect(tun['auto-route'], isTrue);
    expect(tun['mtu'], 1500);
  });

  test('profile 序列化保留 tun', () {
    final profile = Profile(
      id: 'c40ba91d-1e63-46f0-8bab-74d0cb1159c0',
      displayName: 'tun',
      nodes: const [],
      rules: const [],
      tun: const TunOptions(enabled: true, mtu: 1280),
    );
    final restored = Profile.fromText(jsonEncode(profile.toJson()));
    expect(restored.tun.enabled, isTrue);
    expect(restored.tun.mtu, 1280);
  });

  test('协助进程参数包含开机自启与提权', () {
    final args = HelperClient.createTaskArgs(r'C:\app\flvp-core-host.exe');
    expect(args, contains('/SC'));
    expect(args, contains('ONSTART'));
    expect(args, contains('SYSTEM'));
    expect(args.last, contains('--elevated-serve'));
    final command = HelperClient.elevatedCommand(args);
    expect(command, contains('RunAs'));
    expect(command, contains('schtasks.exe'));
    expect(HelperClient.deleteTaskArgs(), contains('/Delete'));
  });
}
