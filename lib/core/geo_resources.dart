import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'profile.dart';

/// Geo 资源（geoip.dat / geosite.dat）的本地管理与按需获取。
///
/// 内核只从数据目录读取 `geoip.dat` 与 `geosite.dat`，缺文件或缺少类别时会
/// 静默跳过 GEOIP / GEOSITE 规则。因此启用这类规则前必须先把资源准备好，
/// 这里负责下载、尺寸校验、按名称原子替换，并把摘要记录到 `meta.json`。
class GeoResources {
  GeoResources(this.root);
  final Directory root;

  static const geoip = 'geoip.dat';
  static const geosite = 'geosite.dat';

  /// 默认来源：社区维护的 v2ray-rules-dat 发布包，体积与类别覆盖面稳定。
  static const sources = <String, String>{
    geoip:
        'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    geosite:
        'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
  };

  static const minBytes = 4 * 1024;
  static const maxBytes = 96 * 1024 * 1024;

  File file(String name) => File(p.join(root.path, name));

  Future<bool> isReady(String name) async {
    final target = file(name);
    if (!await target.exists()) return false;
    final length = await target.length();
    return length >= minBytes && length <= maxBytes;
  }

  /// 该配置需要但尚未就绪的资源名称；只看启用的规则。
  Future<Set<String>> missingFor(Profile profile) async {
    final required = <String>{};
    for (final rule in profile.rules) {
      if (!rule.enabled) continue;
      if (rule.kind == RuleKind.geoIp) required.add(geoip);
      if (rule.kind == RuleKind.geoSite) required.add(geosite);
    }
    final missing = <String>{};
    for (final name in required) {
      if (!await isReady(name)) missing.add(name);
    }
    return missing;
  }

  /// 确保 [profile] 需要的 Geo 资源就绪；[fetch] 可注入，便于测试。
  Future<void> ensureFor(
    Profile profile, {
    Future<List<int>> Function(Uri uri)? fetch,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final missing = await missingFor(profile);
    if (missing.isEmpty) return;
    await root.create(recursive: true);
    for (final name in missing) {
      final uri = Uri.parse(sources[name]!);
      final bytes = await (fetch ?? _download)(uri).timeout(timeout);
      requireConfig(
        bytes.length >= minBytes && bytes.length <= maxBytes,
        'Geo 资源 $name 大小异常，已拒绝写入',
      );
      await install(name, bytes);
    }
  }

  /// 原子替换资源文件，并在 `meta.json` 记录尺寸、摘要与来源。
  Future<void> install(String name, List<int> bytes) async {
    await root.create(recursive: true);
    final target = file(name);
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    await _record(name, bytes);
  }

  Future<void> _record(String name, List<int> bytes) async {
    final meta = File(p.join(root.path, 'meta.json'));
    var data = <String, Object?>{};
    if (await meta.exists()) {
      try {
        final decoded = jsonDecode(await meta.readAsString());
        if (decoded is Map<String, Object?>) data = decoded;
      } on FormatException {
        data = <String, Object?>{};
      }
    }
    data[name] = <String, Object?>{
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'source': sources[name],
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final temporary = File('${meta.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(data), flush: true);
      if (await meta.exists()) await meta.delete();
      await temporary.rename(meta.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<List<int>> _download(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = true;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'FLVPcore/0.1 geo');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ConfigurationException('Geo 资源下载失败：HTTP ${response.statusCode}');
      }
      final builder = <int>[];
      await for (final chunk in response) {
        builder.addAll(chunk);
        if (builder.length > maxBytes) {
          throw const ConfigurationException('Geo 资源超过大小上限，已中止下载');
        }
      }
      return builder;
    } on ConfigurationException {
      rethrow;
    } on Object catch (error) {
      throw ConfigurationException('Geo 资源下载失败：${error.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }
}
