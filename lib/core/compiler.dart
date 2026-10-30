import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'profile.dart';

String canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map<String, dynamic>) {
      return SplayTreeMap<String, Object?>.from(
        item.map((key, value) => MapEntry(key, sort(value))),
      );
    }
    if (item is List) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}

String contentHash(String text) => sha256.convert(utf8.encode(text)).toString();

class CompiledConfig {
  const CompiledConfig({
    required this.text,
    required this.runtimeHash,
    required this.logicalHash,
    required this.mixedPort,
  });
  final String text;
  final String runtimeHash;
  final String logicalHash;
  final int mixedPort;
}

class ConfigCompiler {
  const ConfigCompiler();
  static const version = 'm0.1';

  CompiledConfig compile(
    Profile profile, {
    required int mixedPort,
    String? selectedNodeId,
  }) {
    profile.validate();
    requireConfig(
      mixedPort >= 1024 && mixedPort <= 65535,
      '本地代理端口必须为 1024–65535',
    );
    requireConfig(
      selectedNodeId == null ||
          selectedNodeId == directTarget ||
          profile.nodes.any((n) => n.id == selectedNodeId),
      '选择的节点已不存在',
    );
    String target(String id) => switch (id) {
      directTarget => 'DIRECT',
      rejectTarget => 'REJECT',
      proxyTarget => 'PROXY',
      _ => profile.nodes.firstWhere((n) => n.id == id).coreName,
    };
    final members = [...profile.nodes.map((n) => n.coreName), 'DIRECT'];
    if (selectedNodeId != null) {
      final selected = target(selectedNodeId);
      members.remove(selected);
      members.insert(0, selected);
    }
    final rules = <String>[];
    if (profile.mode == RoutingMode.rule) {
      for (final rule in profile.rules.where((r) => r.enabled)) {
        rules.add(
          '${rule.coreType},${rule.value},${target(rule.targetId)}${rule.noResolve ? ',no-resolve' : ''}',
        );
      }
    }
    final finalTarget = switch (profile.mode) {
      RoutingMode.direct => 'DIRECT',
      RoutingMode.global => 'PROXY',
      RoutingMode.rule => target(profile.finalTargetId),
    };
    rules.add('MATCH,$finalTarget');
    final text = canonicalJson(<String, dynamic>{
      'mixed-port': mixedPort,
      'allow-lan': false,
      'bind-address': '127.0.0.1',
      'mode': 'rule',
      'log-level': 'warn',
      'ipv6': false,
      'dns': {'enable': false},
      'tun': {'enable': false, 'auto-route': false},
      'proxies': [
        for (final node in profile.nodes)
          {
            'name': node.coreName,
            'type': node.protocol.name,
            'server': node.server,
            'port': node.port,
          },
      ],
      'proxy-groups': [
        {'name': 'PROXY', 'type': 'select', 'proxies': members},
      ],
      'rules': rules,
    });
    requireConfig(utf8.encode(text).length <= 512 * 1024, '生成的配置超过 512 KiB');
    final logicalHash = contentHash(
      canonicalJson(<String, dynamic>{
        'compilerVersion': version,
        'profile': profile.toJson(),
        'selectedNodeId': selectedNodeId,
      }),
    );
    return CompiledConfig(
      text: text,
      runtimeHash: contentHash(text),
      logicalHash: logicalHash,
      mixedPort: mixedPort,
    );
  }
}
