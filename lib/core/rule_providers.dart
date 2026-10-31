import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'profile.dart';

const maxProviderBytes = 16 * 1024 * 1024;
const maxProviderCount = 32;
const providerBehaviors = {'domain', 'ipcidr', 'classical'};

/// Clash `rule-providers` 的本地落地。
///
/// 内核自己支持 RULE-SET（按 behavior 建域名树 / 网段集合），所以这里不把规则
/// 展开进 Profile（十万级条目会变成上万条规则），而是把每个被引用的 provider
/// 原始 payload 下载到 `providers/`，再用索引告诉宿主名字、behavior 与文件名。
///
/// 每份配置的索引单独存为 `<sourceId>.json`，激活时再发布成 `index.json`，
/// 这样多份配置不会互相覆盖，也不需要激活时重新联网。
class RuleProviderStore {
  RuleProviderStore(this.root);
  final Directory root;

  /// 宿主实际读取的索引。
  File get index => File(p.join(root.path, 'index.json'));

  File manifest(String sourceId) => File(p.join(root.path, '$sourceId.json'));

  static final _sourceId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// 下载 [text] 里被引用的 provider，写入该配置的索引并发布为当前索引。
  Future<void> ensureFor(
    String sourceId,
    String text, {
    Future<String> Function(Uri uri)? fetch,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    requireConfig(_sourceId.hasMatch(sourceId), '配置标识无效');
    final trimmed = text.trim().replaceFirst('\uFEFF', '');
    await root.create(recursive: true);
    if (!trimmed.contains('rule-providers')) {
      await _publish(sourceId, const []);
      return;
    }
    Object? document;
    try {
      document = loadYaml(trimmed);
    } on YamlException {
      throw const ConfigurationException('rule-providers 所在文档不是有效的 YAML');
    }
    requireConfig(document is Map, '配置必须是对象');
    final data = document as Map;
    final providers = data['rule-providers'];
    requireConfig(providers is Map, 'rule-providers 必须为对象');
    requireConfig(
      providers.length <= maxProviderCount,
      'rule-providers 数量超过 $maxProviderCount',
    );
    final used = <String>[];
    final rules = data['rules'];
    if (rules is List) {
      for (final entry in rules) {
        if (entry is! String) continue;
        final fields = entry.split(',').map((value) => value.trim()).toList();
        if (fields.first != 'RULE-SET' || fields.length < 3) continue;
        if (!used.contains(fields[1])) used.add(fields[1]);
      }
    }
    for (final name in used) {
      requireConfig(providers.containsKey(name), '规则集 $name 未在 rule-providers 中定义');
    }
    final entries = <Map<String, Object?>>[];
    for (final name in used) {
      final provider = providers[name];
      requireConfig(provider is Map, '规则集 $name 必须是对象');
      final behavior = provider['behavior'];
      requireConfig(
        behavior is String && providerBehaviors.contains(behavior),
        '规则集 $name 的 behavior ${behavior ?? ''} 尚未支持',
      );
      final type = provider['type'];
      requireConfig(
        type is String && (type == 'http' || type == 'https'),
        '规则集 $name 的 type ${type ?? ''} 尚未支持',
      );
      final raw = provider['url'];
      requireConfig(raw is String && raw.isNotEmpty, '规则集 $name 缺少 url');
      final uri = Uri.tryParse(raw);
      requireConfig(
        uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty,
        '规则集 $name 的 url 无效',
      );
      final body = await (fetch ?? _download)(uri!).timeout(timeout);
      requireConfig(body.trim().isNotEmpty, '规则集 $name 内容为空');
      final bytes = utf8.encode(body).length;
      requireConfig(bytes <= maxProviderBytes, '规则集 $name 超过大小上限');
      final file = '$sourceId-${_slug(name)}.txt';
      await _write(p.join(root.path, file), body);
      entries.add({
        'name': name,
        'behavior': behavior,
        'file': file,
        'bytes': bytes,
      });
    }
    await _publish(sourceId, entries);
  }

  /// 激活某份配置的索引；尚未下载时返回 false。
  Future<bool> activate(String sourceId) async {
    final source = manifest(sourceId);
    if (!await source.exists()) return false;
    await _write(index.path, await source.readAsString());
    return true;
  }

  /// 删除某份配置的索引与它的 payload 文件。
  Future<void> forget(String sourceId) async {
    final source = manifest(sourceId);
    if (!await source.exists()) return;
    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is Map && decoded['providers'] is List) {
        for (final entry in decoded['providers'] as List) {
          if (entry is Map && entry['file'] is String) {
            final file = File(p.join(root.path, entry['file'] as String));
            if (await file.exists()) await file.delete();
          }
        }
      }
    } on FormatException {
      // 损坏的索引只需删掉索引本身。
    }
    await source.delete();
  }

  Future<void> _publish(String sourceId, List<Map<String, Object?>> entries) async {
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'providers': entries,
    });
    await _write(manifest(sourceId).path, encoded);
    await _write(index.path, encoded);
  }

  Future<void> _write(String path, String body) async {
    final temporary = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await temporary.writeAsString(body, flush: true);
      final target = File(path);
      if (await target.exists()) await target.delete();
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _slug(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final digest = sha256.convert(utf8.encode(name)).toString().substring(0, 8);
    return '${safe.length > 40 ? safe.substring(0, 40) : safe}-$digest';
  }

  Future<String> _download(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'FLVPcore/0.1 rule-provider');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ConfigurationException('规则集下载失败：HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxProviderBytes) {
          throw const ConfigurationException('规则集超过大小上限，已中止下载');
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on ConfigurationException {
      rethrow;
    } on Object catch (error) {
      throw ConfigurationException('规则集下载失败：${error.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }
}
