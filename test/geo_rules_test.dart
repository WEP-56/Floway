import 'dart:convert';
import 'dart:io';

import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/geo_resources.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _clash = '''
mixed-port: 7890
mode: rule
proxies:
  - name: local
    type: socks5
    server: 127.0.0.1
    port: 1080
proxy-groups:
  - name: Proxy
    type: select
    proxies: [local, DIRECT]
rules:
  - GEOIP,cn,DIRECT
  - GEOSITE,category-ads-all,Proxy
  - MATCH,Proxy
''';

void main() {
  const importer = ConfigurationImporter();

  test('Geo rules are imported and compiled for the kernel', () {
    final profile = importer.parse(_clash, name: 'Geo');
    expect(profile.rules.map((rule) => rule.coreType), [
      'GEOIP',
      'GEOSITE',
    ]);
    expect(profile.rules.first.value, 'CN');
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
      selectedNodeId: profile.nodes.first.id,
    );
    final rules = (jsonDecode(compiled.text)['rules'] as List).cast<String>();
    expect(rules.first, 'GEOIP,CN,DIRECT');
    expect(rules[1], startsWith('GEOSITE,category-ads-all,group_'));
    expect(rules.last, startsWith('MATCH,group_'));
  });

  test('Invalid geo categories are rejected', () {
    for (final rule in [
      'GEOIP,cn/us,DIRECT',
      'GEOSITE,,DIRECT',
      'GEOSITE,a b,DIRECT',
    ]) {
      final text = _clash.replaceFirst('GEOIP,cn,DIRECT', rule);
      expect(
        () => importer.parse(text, name: '坏配置'),
        throwsA(isA<ConfigurationException>()),
        reason: rule,
      );
    }
  });

  test('Geo resources are downloaded, verified and recorded', () async {
    final dir = await Directory.systemTemp.createTemp('flvp-geo');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final geo = GeoResources(dir);
    final bytes = List<int>.generate(8192, (i) => i % 251);
    final requested = <String>[];
    await geo.ensureFor(
      importer.parse(_clash, name: 'Geo'),
      fetch: (uri) async {
        requested.add(uri.path);
        return bytes;
      },
    );
    expect(requested.length, 2);
    expect(await geo.file(GeoResources.geoip).length(), 8192);
    expect(await geo.file(GeoResources.geosite).length(), 8192);
    final meta =
        jsonDecode(await File(p.join(dir.path, 'meta.json')).readAsString())
            as Map<String, Object?>;
    expect((meta[GeoResources.geoip] as Map)['size'], 8192);
    expect((meta[GeoResources.geosite] as Map)['sha256'], hasLength(64));

    var calls = 0;
    await geo.ensureFor(
      importer.parse(_clash, name: 'Geo'),
      fetch: (uri) async {
        calls++;
        return bytes;
      },
    );
    expect(calls, 0);
  });

  test('Oversized or truncated downloads are refused', () async {
    final dir = await Directory.systemTemp.createTemp('flvp-geo-bad');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final geo = GeoResources(dir);
    await expectLater(
      geo.ensureFor(
        importer.parse(_clash, name: 'Geo'),
        fetch: (uri) async => List<int>.filled(16, 1),
      ),
      throwsA(isA<ConfigurationException>()),
    );
    expect(await geo.file(GeoResources.geoip).exists(), isFalse);
  });
}
