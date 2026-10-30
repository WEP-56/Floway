import 'dart:convert';

import 'compiler.dart';
import 'profile.dart';

enum ConfigurationSourceKind { remote, file, manual }

/// Source text is an app-owned snapshot; never reread an imported file path.
/// Profile is the typed editable model. Runtime snapshots remain separate.
class ConfigurationSource {
  const ConfigurationSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.original,
    required this.profile,
    required this.selectedNodeId,
    required this.updatedAt,
    this.url,
  });
  final String id;
  final String name;
  final ConfigurationSourceKind kind;
  final String original;
  final Profile profile;
  final String selectedNodeId;
  final DateTime updatedAt;
  final String? url;

  ConfigurationSource withProfile(Profile value, String selection) =>
      ConfigurationSource(
        id: id,
        name: name,
        kind: kind,
        original: original,
        profile: value,
        selectedNodeId: selection,
        updatedAt: updatedAt,
        url: url,
      );

  void validate() {
    requireConfig(validId(id), '配置来源 ID 无效');
    requireConfig(
      name.trim().isNotEmpty && name.length <= 100,
      '配置名称需为 1–100 个字符',
    );
    requireConfig(utf8.encode(original).length <= 1024 * 1024, '来源原文超过 1 MiB');
    if (kind == ConfigurationSourceKind.remote) {
      final uri = Uri.tryParse(url ?? '');
      requireConfig(
        uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasFragment,
        '订阅地址须为 HTTP(S) 链接，不支持 URL 用户认证或片段',
      );
    } else {
      requireConfig(url == null, '本地配置不应包含订阅地址');
    }
    profile.validate();
    requireConfig(
      selectedNodeId == directTarget ||
          profile.nodes.any((n) => n.id == selectedNodeId),
      '配置内选择的节点不存在',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'original': original,
    'originalHash': contentHash(original),
    'profile': profile.toJson(),
    'selectedNodeId': selectedNodeId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'url': url,
  };

  factory ConfigurationSource.fromJson(Object? value) {
    final map = jsonObject(value, {
      'id',
      'name',
      'kind',
      'original',
      'originalHash',
      'profile',
      'selectedNodeId',
      'updatedAt',
      'url',
    }, '配置来源');
    final original = jsonText(map, 'original');
    requireConfig(contentHash(original) == map['originalHash'], '来源快照摘要不匹配');
    final source = ConfigurationSource(
      id: jsonText(map, 'id'),
      name: jsonText(map, 'name'),
      kind: enumValue(ConfigurationSourceKind.values, map['kind'], '配置来源类型'),
      original: original,
      profile: Profile.fromJson(map['profile']),
      selectedNodeId: jsonText(map, 'selectedNodeId'),
      updatedAt: DateTime.parse(jsonText(map, 'updatedAt')),
      url: map['url'] as String?,
    );
    source.validate();
    return source;
  }
}

class ConfigurationLibrary {
  ConfigurationLibrary({
    List<ConfigurationSource> sources = const [],
    this.activeId,
  }) : sources = List.unmodifiable(sources);
  final List<ConfigurationSource> sources;
  final String? activeId;
  ConfigurationSource? get active =>
      sources.where((s) => s.id == activeId).firstOrNull;
  ConfigurationSource source(String id) => sources.firstWhere(
    (s) => s.id == id,
    orElse: () => throw const ConfigurationException('配置已不存在'),
  );
  ConfigurationLibrary upsert(
    ConfigurationSource value, {
    bool activate = false,
  }) => ConfigurationLibrary(
    sources: [...sources.where((s) => s.id != value.id), value],
    activeId: activate ? value.id : activeId,
  );
  ConfigurationLibrary select(String id) {
    source(id);
    return ConfigurationLibrary(sources: sources, activeId: id);
  }

  ConfigurationLibrary remove(String id) {
    requireConfig(id != activeId, '请先切换到其他配置再删除当前配置');
    return ConfigurationLibrary(
      sources: sources.where((s) => s.id != id).toList(),
      activeId: activeId,
    );
  }

  ConfigurationLibrary saveActive(Profile profile, String selection) =>
      active == null ? this : upsert(active!.withProfile(profile, selection));
  void validate() {
    requireConfig(sources.length <= 64, '最多保存 64 份配置');
    final ids = <String>{};
    for (final source in sources) {
      source.validate();
      requireConfig(ids.add(source.id), '配置来源 ID 重复');
    }
    requireConfig(
      activeId == null ? sources.isEmpty : ids.contains(activeId),
      '活动配置引用无效',
    );
    requireConfig(
      utf8.encode(jsonEncode(toJson())).length <= 16 * 1024 * 1024,
      '配置仓库超过 16 MiB',
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'activeId': activeId,
    'sources': sources.map((s) => s.toJson()).toList(),
  };
  factory ConfigurationLibrary.fromJson(Object? value) {
    if (value == null) return ConfigurationLibrary();
    final map = jsonObject(value, {
      'schemaVersion',
      'activeId',
      'sources',
    }, '配置仓库');
    requireConfig(
      map['schemaVersion'] == 1 && map['sources'] is List,
      '配置仓库版本无效',
    );
    final library = ConfigurationLibrary(
      sources: (map['sources'] as List)
          .map(ConfigurationSource.fromJson)
          .toList(),
      activeId: map['activeId'] as String?,
    );
    library.validate();
    return library;
  }
}
