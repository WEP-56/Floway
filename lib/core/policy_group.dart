part of 'profile.dart';

enum GroupKind { select, urlTest, fallback }

class PolicyGroup {
  PolicyGroup({
    required this.id,
    required this.displayName,
    required this.kind,
    required List<String> members,
    this.selectedId,
    this.url,
    this.interval = 300,
    this.tolerance = 0,
  }) : members = List.unmodifiable(members);
  final String id, displayName;
  final GroupKind kind;
  final List<String> members;
  final String? selectedId, url;
  final int interval, tolerance;
  String get coreName => 'group_${id.replaceAll('-', '_')}';
  String get coreType => switch (kind) {
    GroupKind.select => 'select',
    GroupKind.urlTest => 'url-test',
    GroupKind.fallback => 'fallback',
  };
  PolicyGroup select(String member) {
    requireConfig(
      kind == GroupKind.select && members.contains(member),
      '策略组选择无效',
    );
    return PolicyGroup(
      id: id,
      displayName: displayName,
      kind: kind,
      members: members,
      selectedId: member,
      url: url,
      interval: interval,
      tolerance: tolerance,
    );
  }

  void validate() {
    requireConfig(
      validId(id) && displayName.trim().isNotEmpty && displayName.length <= 100,
      '策略组 ID 或名称无效',
    );
    requireConfig(
      members.isNotEmpty &&
          members.length <= 320 &&
          members.toSet().length == members.length,
      '策略组成员为空、重复或过多',
    );
    requireConfig(
      selectedId == null ||
          (kind == GroupKind.select && members.contains(selectedId)),
      '策略组选择目标不存在或不支持手动选择',
    );
    if (kind == GroupKind.select) {
      requireConfig(
        url == null && interval == 300 && tolerance == 0,
        '手动策略组不支持健康检查参数',
      );
    } else {
      final uri = url == null ? null : Uri.tryParse(url!);
      requireConfig(
        uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasFragment &&
            !uri.host.contains(':') &&
            RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*$').hasMatch(uri.host) &&
            (uri.path.isNotEmpty || !uri.hasQuery) &&
            url!.length <= 2048 &&
            !RegExp(r'[\x00-\x20\x7f]').hasMatch(url!),
        '健康检查 URL 无效（仅 HTTP(S) 域名/IPv4）',
      );
      requireConfig(
        uri!.port > 0 &&
            uri.port <= 65535 &&
            !(uri.scheme == 'http' && uri.port == 443),
        '健康检查 URL 端口不受支持',
      );
      requireConfig(
        interval >= 30 &&
            interval <= 86400 &&
            tolerance >= 0 &&
            tolerance <= 60000,
        '健康检查间隔或容差超限',
      );
      requireConfig(
        kind == GroupKind.urlTest || tolerance == 0,
        'Fallback 不支持容差',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'kind': kind.name,
    'members': members,
    'selectedId': selectedId,
    'url': url,
    'interval': interval,
    'tolerance': tolerance,
  };
  factory PolicyGroup.fromJson(Object? value) {
    final m = jsonObject(value, {
      'id',
      'displayName',
      'kind',
      'members',
      'selectedId',
      'url',
      'interval',
      'tolerance',
    }, '策略组');
    requireConfig(
      m['members'] is List &&
          (m['members'] as List).every((v) => v is String) &&
          m['interval'] is int &&
          m['tolerance'] is int &&
          (m['selectedId'] == null || m['selectedId'] is String) &&
          (m['url'] == null || m['url'] is String),
      '策略组字段类型无效',
    );
    return PolicyGroup(
      id: jsonText(m, 'id'),
      displayName: jsonText(m, 'displayName'),
      kind: enumValue(GroupKind.values, m['kind'], '策略组类型'),
      members: List<String>.from(m['members'] as List),
      selectedId: m['selectedId'] as String?,
      url: m['url'] as String?,
      interval: m['interval'] as int,
      tolerance: m['tolerance'] as int,
    );
  }
}
