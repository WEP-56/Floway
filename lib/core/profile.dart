import 'dart:convert';
import 'dart:io';

part 'node_options.dart';
part 'policy_group.dart';

enum RoutingMode { rule, global, direct }

enum NodeProtocol {
  socks5,
  http,
  ss,
  vmess,
  vless,
  trojan,
  anytls,
  hysteria,
  hysteria2,
}

enum RuleKind {
  domain,
  domainSuffix,
  domainKeyword,
  ipCidr,
  network,
  destinationPort,
}

const directTarget = 'builtin:direct';
const rejectTarget = 'builtin:reject';
const proxyTarget = 'group:proxy';

class ConfigurationException implements Exception {
  const ConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

void requireConfig(bool condition, String message) {
  if (!condition) throw ConfigurationException(message);
}

Map<String, dynamic> jsonObject(Object? value, Set<String> keys, String path) {
  requireConfig(value is Map<String, dynamic>, '$path 必须是对象');
  final object = value! as Map<String, dynamic>;
  requireConfig(object.keys.every(keys.contains), '$path 包含当前版本不支持的字段');
  return object;
}

String jsonText(Map<String, dynamic> object, String key) {
  requireConfig(object[key] is String, '$key 必须是字符串');
  return object[key] as String;
}

T enumValue<T extends Enum>(List<T> values, Object? value, String name) {
  final matches = values.where((item) => item.name == value);
  requireConfig(matches.length == 1, '$name 不受当前版本支持');
  return matches.single;
}

bool validId(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value);

class ProxyNode {
  const ProxyNode({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.server,
    required this.port,
    this.options = const NodeOptions(),
  });
  final String id;
  final String displayName;
  final NodeProtocol protocol;
  final String server;
  final int port;
  final NodeOptions options;
  String get coreName => 'node_${id.replaceAll('-', '_')}';

  void validate() {
    options.validate(protocol);
    requireConfig(validId(id), '节点 ID 必须是 UUID');
    requireConfig(
      displayName.trim().isNotEmpty && displayName.length <= 100,
      '节点名称需为 1–100 个字符',
    );
    requireConfig(port >= 1 && port <= 65535, '节点端口必须为 1–65535');
    requireConfig(
      server.isNotEmpty &&
          server.length <= 253 &&
          (InternetAddress.tryParse(server) != null ||
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$')
                  .hasMatch(server)),
      '服务器须为 IP 或 ASCII 域名，不包含协议、端口或路径',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'protocol': protocol.name,
    'server': server,
    'port': port,
    'options': options.toJson(),
  };

  factory ProxyNode.fromJson(Object? value) {
    final map = jsonObject(value, {
      'id',
      'displayName',
      'protocol',
      'server',
      'port',
      'options',
    }, 'node');
    requireConfig(map['port'] is int, '节点端口必须是整数');
    final node = ProxyNode(
      id: jsonText(map, 'id'),
      displayName: jsonText(map, 'displayName'),
      protocol: enumValue(NodeProtocol.values, map['protocol'], '节点协议'),
      server: jsonText(map, 'server'),
      port: map['port'] as int,
      options: NodeOptions.fromJson(map['options'] ?? <String, dynamic>{}),
    );
    node.validate();
    return node;
  }
}

class RuleSpec {
  const RuleSpec({
    required this.id,
    required this.kind,
    required this.value,
    required this.targetId,
    this.enabled = true,
    this.noResolve = false,
  });
  final String id;
  final RuleKind kind;
  final String value;
  final String targetId;
  final bool enabled;
  final bool noResolve;

  String get coreType => switch (kind) {
    RuleKind.domain => 'DOMAIN',
    RuleKind.domainSuffix => 'DOMAIN-SUFFIX',
    RuleKind.domainKeyword => 'DOMAIN-KEYWORD',
    RuleKind.ipCidr => 'IP-CIDR',
    RuleKind.network => 'NETWORK',
    RuleKind.destinationPort => 'DST-PORT',
  };

  void validate() {
    requireConfig(validId(id), '规则 ID 必须是 UUID');
    requireConfig(
      value.isNotEmpty &&
          value.length <= 253 &&
          !RegExp(r'[,\s()]').hasMatch(value),
      '规则参数为空或包含不支持的分隔符',
    );
    requireConfig(
      !noResolve || kind == RuleKind.ipCidr,
      'no-resolve 只适用于 IP 规则',
    );
    switch (kind) {
      case RuleKind.domain:
      case RuleKind.domainSuffix:
        requireConfig(
          RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$')
              .hasMatch(value),
          '域名规则须使用 ASCII 域名',
        );
      case RuleKind.domainKeyword:
        break;
      case RuleKind.ipCidr:
        final parts = value.split('/');
        final address = InternetAddress.tryParse(parts.first);
        final prefix = parts.length == 2 ? int.tryParse(parts.last) : null;
        requireConfig(
          address != null &&
              prefix != null &&
              prefix >= 0 &&
              prefix <= (address.type == InternetAddressType.IPv4 ? 32 : 128),
          'CIDR 无效',
        );
      case RuleKind.network:
        requireConfig(
          value == 'TCP' || value == 'UDP',
          'NETWORK 只支持 TCP / UDP',
        );
      case RuleKind.destinationPort:
        final port = int.tryParse(value);
        requireConfig(
          port != null && port >= 1 && port <= 65535,
          '规则端口必须为 1–65535',
        );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'value': value,
    'targetId': targetId,
    'enabled': enabled,
    'noResolve': noResolve,
  };

  factory RuleSpec.fromJson(Object? value) {
    final map = jsonObject(value, {
      'id',
      'kind',
      'value',
      'targetId',
      'enabled',
      'noResolve',
    }, 'rule');
    requireConfig(
      map['enabled'] is bool && map['noResolve'] is bool,
      '规则开关必须是布尔值',
    );
    return RuleSpec(
      id: jsonText(map, 'id'),
      kind: enumValue(RuleKind.values, map['kind'], '规则类型'),
      value: jsonText(map, 'value'),
      targetId: jsonText(map, 'targetId'),
      enabled: map['enabled'] as bool,
      noResolve: map['noResolve'] as bool,
    );
  }
}

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required List<ProxyNode> nodes,
    required List<RuleSpec> rules,
    List<PolicyGroup> groups = const [],
    this.revision = 1,
    this.mode = RoutingMode.rule,
    this.finalTargetId = directTarget,
  }) : nodes = List.unmodifiable(nodes),
       rules = List.unmodifiable(rules),
       groups = List.unmodifiable(groups);

  factory Profile.initial() => Profile(
    id: 'c40ba91d-1e63-46f0-8bab-74d0cb1159c0',
    displayName: '本地直连测试',
    nodes: [],
    rules: [],
  );

  final String id;
  final String displayName;
  final int revision;
  final RoutingMode mode;
  final String finalTargetId;
  final List<ProxyNode> nodes;
  final List<RuleSpec> rules;
  final List<PolicyGroup> groups;

  Profile copyWith({
    String? displayName,
    List<ProxyNode>? nodes,
    List<RuleSpec>? rules,
    List<PolicyGroup>? groups,
    RoutingMode? mode,
    String? finalTargetId,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    revision: revision + 1,
    mode: mode ?? this.mode,
    finalTargetId: finalTargetId ?? this.finalTargetId,
    nodes: nodes ?? this.nodes,
    rules: rules ?? this.rules,
    groups: groups ?? this.groups,
  );

  void validate() {
    requireConfig(validId(id), '配置 ID 必须是 UUID');
    requireConfig(
      revision >= 1 && revision <= 0x1fffffffffffff,
      '配置 revision 无效',
    );
    requireConfig(
      displayName.trim().isNotEmpty && displayName.length <= 100,
      '配置名称无效',
    );
    requireConfig(nodes.length <= 256 && rules.length <= 4095, '超出当前版本配置数量上限');
    final ids = <String>{};
    for (final node in nodes) {
      node.validate();
      requireConfig(ids.add(node.id), '节点 ID 重复');
    }
    requireConfig(groups.length <= 64, '策略组不能超过 64 个');
    final groupNames = <String>{};
    for (final group in groups) {
      group.validate();
      requireConfig(ids.add(group.id), '节点/策略组 ID 重复');
      requireConfig(groupNames.add(group.displayName), '策略组名称重复');
    }
    final targets = {
      directTarget,
      rejectTarget,
      proxyTarget,
      ...nodes.map((n) => n.id),
      ...groups.map((g) => g.id),
    };
    final byId = {for (final g in groups) g.id: g};
    final depths = <String, int>{}, visiting = <String>{};
    int visit(String id) {
      if (depths.containsKey(id)) return depths[id]!;
      requireConfig(visiting.add(id), '策略组存在循环引用');
      var height = 1;
      for (final member in byId[id]!.members) {
        requireConfig(
          targets.contains(member) && member != proxyTarget,
          '策略组成员不存在或引用了保留的全局选择器',
        );
        if (byId.containsKey(member)) {
          final childHeight = 1 + visit(member);
          if (childHeight > height) height = childHeight;
        }
      }
      requireConfig(height <= 16, '策略组嵌套不能超过 16 层');
      visiting.remove(id);
      return depths[id] = height;
    }

    for (final group in groups) {
      visit(group.id);
    }
    requireConfig(targets.contains(finalTargetId), '最终规则目标不存在');
    final ruleIds = <String>{};
    for (final rule in rules) {
      rule.validate();
      requireConfig(ruleIds.add(rule.id), '规则 ID 重复');
      requireConfig(targets.contains(rule.targetId), '规则目标不存在');
    }
  }

  Map<String, Object?> toJson() => {
    'format': 'flvp-profile',
    'schemaVersion': 1,
    'profileId': id,
    'revision': revision,
    'displayName': displayName,
    'policy': {'mode': mode.name, 'finalTargetId': finalTargetId},
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'rules': rules.map((r) => r.toJson()).toList(),
    'groups': groups.map((g) => g.toJson()).toList(),
  };

  factory Profile.fromText(String text) {
    requireConfig(utf8.encode(text).length <= 1024 * 1024, '配置超过 1 MiB');
    return Profile.fromJson(jsonDecode(text));
  }

  factory Profile.fromJson(Object? value) {
    final map = jsonObject(value, {
      'format',
      'schemaVersion',
      'profileId',
      'revision',
      'displayName',
      'policy',
      'nodes',
      'rules',
      'groups',
    }, 'profile');
    requireConfig(
      map['format'] == 'flvp-profile' && map['schemaVersion'] == 1,
      '仅支持 flvp-profile v1；尚不支持直接导入订阅或内核配置',
    );
    final policy = jsonObject(map['policy'], {
      'mode',
      'finalTargetId',
    }, 'policy');
    requireConfig(
      map['revision'] is int &&
          map['nodes'] is List &&
          map['rules'] is List &&
          (!map.containsKey('groups') || map['groups'] is List),
      '配置字段类型无效',
    );
    final profile = Profile(
      id: jsonText(map, 'profileId'),
      displayName: jsonText(map, 'displayName'),
      revision: map['revision'] as int,
      mode: enumValue(RoutingMode.values, policy['mode'], '代理模式'),
      finalTargetId: jsonText(policy, 'finalTargetId'),
      nodes: (map['nodes'] as List).map(ProxyNode.fromJson).toList(),
      rules: (map['rules'] as List).map(RuleSpec.fromJson).toList(),
      groups: (map['groups'] as List? ?? []).map(PolicyGroup.fromJson).toList(),
    );
    profile.validate();
    return profile;
  }
}
