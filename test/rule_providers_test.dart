import 'dart:convert';
import 'dart:io';

import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/rule_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _clash = '''
mixed-port: 7890
mode: rule
rule-providers:
  ads:
    type: http
    behavior: domain
    url: https://example.test/ads.txt
    interval: 86400
  cn:
    type: http
    behavior: ipcidr
    url: https://example.test/cn.txt
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
  - RULE-SET,ads,REJECT
  - RULE-SET,cn,DIRECT
  - MATCH,Proxy
''';

const _bodies = <String, String>{
  'https://example.test/ads.txt': "payload:\n  - '+.doubleclick.net'\n",
  'https://example.test/cn.txt': "1.2.3.0/24\n10.0.0.0/8\n",
};

Future<String> _fetch(Uri uri) async {
  final body = _bodies[uri.toString()];
  if (body == null) throw const ConfigurationException('缺少固定响应');
  return body;
}

Future<Directory> _temp([String prefix = 'flvp-provider']) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

void main() {
  const importer = ConfigurationImporter();

  test('rule sets stay typed rules and land as local payload files', () async {
    final dir = await _temp();
    final store = RuleProviderStore(dir);
    await store.ensureFor('src', _clash, fetch: _fetch);
    final index =
        jsonDecode(await store.index.readAsString()) as Map<String, Object?>;
    final entries = (index['providers'] as List).cast<Map<String, Object?>>();
    expect(entries.map((entry) => entry['name']), ['ads', 'cn']);
    expect(entries.map((entry) => entry['behavior']), ['domain', 'ipcidr']);
    final file = entries.first['file'] as String;
    expect(file, endsWith('.txt'));
    expect(file, startsWith('src-'));
    expect(
      await File(p.join(dir.path, file)).readAsString(),
      _bodies['https://example.test/ads.txt'],
    );
    expect(await store.activate('src'), isTrue);
    expect(await store.activate('other'), isFalse);

    final profile = importer.parse(_clash, name: 'Provider');
    expect(profile.rules.map((rule) => rule.coreType), ['RULE-SET', 'RULE-SET']);
    expect(profile.rules.map((rule) => rule.value), ['ads', 'cn']);
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
      selectedNodeId: profile.nodes.first.id,
    );
    final rules = (jsonDecode(compiled.text)['rules'] as List).cast<String>();
    expect(rules.take(2), ['RULE-SET,ads,REJECT', 'RULE-SET,cn,DIRECT']);
  });

  test('providers must be defined, http and of a known behavior', () async {
    Future<void> refuses(String yaml) async {
      final dir = await _temp('flvp-provider-bad');
      await expectLater(
        RuleProviderStore(dir).ensureFor('src', yaml, fetch: _fetch),
        throwsA(isA<ConfigurationException>()),
      );
    }

    await refuses(_clash.replaceFirst('behavior: domain', 'behavior: regexp'));
    await refuses(
      _clash.replaceFirst(
        'type: http\n    behavior: domain',
        'type: file\n    behavior: domain',
      ),
    );
    await refuses(
      _clash.replaceFirst('RULE-SET,ads,REJECT', 'RULE-SET,missing,REJECT'),
    );
    await refuses(
      _clash.replaceFirst('    url: https://example.test/ads.txt\n', ''),
    );
  });

  test('importing a provider rule without its definition fails', () {
    expect(
      () => importer.parse(
        _clash.replaceFirst('rule-providers:', 'unknown-key:'),
        name: '坏配置',
      ),
      throwsA(isA<ConfigurationException>()),
    );
  });

  test('a document without providers publishes an empty index', () async {
    final dir = await _temp('flvp-provider-clear');
    final store = RuleProviderStore(dir);
    await store.ensureFor('src', _clash, fetch: _fetch);
    expect(await store.index.exists(), isTrue);
    await store.ensureFor('src', 'mixed-port: 7890\n', fetch: _fetch);
    final index =
        jsonDecode(await store.index.readAsString()) as Map<String, Object?>;
    expect(index['providers'], isEmpty);
    await store.forget('src');
    expect(await store.manifest('src').exists(), isFalse);
  });
}
