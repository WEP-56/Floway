import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'configuration_library.dart';
import 'compiler.dart';
import 'profile.dart';
import 'share_link.dart';

const maxImportBytes = 1024 * 1024;

/// Explicit subset: native profiles preserve all typed semantics; a Clash
/// policy documents preserve references; node-only documents use PROXY.
class ConfigurationImporter {
  const ConfigurationImporter();
  Profile parse(String text, {required String name}) {
    requireConfig(utf8.encode(text).length <= maxImportBytes, '配置超过 1 MiB');
    final trimmed = text.trim().replaceFirst('\uFEFF', '');
    requireConfig(trimmed.isNotEmpty, '配置内容为空');
    try {
      if (trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded['format'] == 'flvp-profile') {
          return Profile.fromJson(decoded);
        }
      }
      if (RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(trimmed)) {
        final decoded = utf8.decode(
          base64.decode(
            base64.normalize(trimmed.replaceAll(RegExp(r'\s'), '')),
          ),
        );
        return _uris(decoded, name);
      }
      if (RegExp(r'^[a-zA-Z][\w+.-]*://').hasMatch(trimmed)) {
        return _uris(trimmed, name);
      }
      final yaml = loadYaml(trimmed);
      requireConfig(
        yaml is Map &&
            yaml.keys.every(
              (k) => {
                'proxies',
                'proxy-groups',
                'rules',
                'mode',
                'mixed-port',
                'port',
                'socks-port',
                'allow-lan',
                'bind-address',
                'external-controller',
                'log-level',
                'dns',
              }.contains(k),
            ),
        '配置包含尚未支持的顶层字段；TUN、provider、Geo 资源及其他内核选项尚未开放',
      );
      final proxies = (yaml as Map)['proxies'];
      requireConfig(
        proxies is List && proxies.isNotEmpty,
        'Clash proxies 必须为非空节点列表',
      );
      final nodes = <ProxyNode>[];
      for (var i = 0; i < (proxies as List).length; i++) {
        final item = proxies[i];
        requireConfig(item is Map, '第 ${i + 1} 个节点必须是对象');
        requireConfig(
          item['name'] is String &&
              item['server'] is String &&
              item['port'] is int,
          '第 ${i + 1} 个节点字段类型无效',
        );
        final protocol = enumValue(
          NodeProtocol.values,
          item['type'],
          '第 ${i + 1} 个节点协议',
        );
        // Normalize YAML into plain JSON before typed parsing. Never copy raw
        // fields into a compiled configuration.
        final parameters = jsonDecode(jsonEncode(item)) as Map<String, dynamic>;
        for (final key in ['name', 'type', 'server', 'port']) {
          parameters.remove(key);
        }
        if (parameters.containsKey('servername')) {
          requireConfig(
            !parameters.containsKey('sni'),
            '第 ${i + 1} 个节点含重复 SNI 字段',
          );
          parameters['sni'] = parameters.remove('servername');
        }
        if (protocol == NodeProtocol.hysteria) {
          for (final key in ['up', 'down']) {
            if (parameters[key] is String) {
              final match = RegExp(
                r'^(\d+)\s*(?:Mbps)?$',
                caseSensitive: false,
              ).firstMatch(parameters[key] as String);
              requireConfig(match != null, 'Hysteria 速率须使用整数 Mbps');
              parameters[key] = int.parse(match!.group(1)!);
            }
          }
        }
        nodes.add(
          ProxyNode(
            id: const Uuid().v4(),
            displayName: item['name'] as String,
            protocol: protocol,
            server: item['server'] as String,
            port: item['port'] as int,
            options: NodeOptions.fromJson(parameters),
          ),
        );
      }
      final profile = _nodeProfile(nodes, name);
      return _clashPolicy(
        jsonDecode(jsonEncode(yaml)) as Map<String, dynamic>,
        profile,
      );
    } on ConfigurationException {
      rethrow;
    } catch (_) {
      // Parser exceptions often contain source lines or credentials.
      throw const ConfigurationException('配置语法或编码无效；未导入任何节点');
    }
  }

  Profile _clashPolicy(Map<String, dynamic> document, Profile base) {
    // Device-owned fields are type-checked but deliberately never applied.
    for (final key in ['mixed-port', 'port', 'socks-port']) {
      if (document.containsKey(key)) {
        requireConfig(
          document[key] is int &&
              (document[key] as int) >= 0 &&
              (document[key] as int) <= 65535,
          '订阅监听端口字段无效',
        );
      }
    }
    requireConfig(
      !document.containsKey('allow-lan') || document['allow-lan'] is bool,
      'allow-lan 必须为布尔值',
    );
    for (final key in ['bind-address', 'external-controller', 'log-level']) {
      requireConfig(
        !document.containsKey(key) || document[key] is String,
        '订阅本机设置字段类型无效',
      );
    }
    final mode = document.containsKey('mode')
        ? enumValue(RoutingMode.values, document['mode'], '模式')
        : RoutingMode.rule;
    final groupData = document.containsKey('proxy-groups')
        ? document['proxy-groups']
        : [];
    requireConfig(
      groupData is List && groupData.length <= 64,
      '策略组必须为列表且不超过 64 个',
    );
    final names = <String, String>{
      'DIRECT': directTarget,
      'REJECT': rejectTarget,
    };
    for (final node in base.nodes) {
      requireConfig(!names.containsKey(node.displayName), '节点/策略组名称重复或使用保留名称');
      names[node.displayName] = node.id;
    }
    final maps = <Map<String, dynamic>>[];
    for (final item in groupData as List) {
      final m = jsonObject(item, {
        'name',
        'type',
        'proxies',
        'url',
        'interval',
        'tolerance',
        'lazy',
      }, 'Clash 策略组');
      final name = jsonText(m, 'name');
      requireConfig(!names.containsKey(name), '节点/策略组名称重复或使用保留名称');
      names[name] = const Uuid().v4();
      maps.add(m);
    }
    String resolve(Object? name) {
      requireConfig(
        name is String && names.containsKey(name),
        '规则或策略组引用了不存在的目标',
      );
      return names[name]!;
    }

    final groups = <PolicyGroup>[];
    for (final m in maps) {
      final kind = switch (m['type']) {
        'select' => GroupKind.select,
        'url-test' => GroupKind.urlTest,
        'fallback' => GroupKind.fallback,
        _ => throw const ConfigurationException(
          '当前策略组仅支持 select、url-test、fallback',
        ),
      };
      requireConfig(m['proxies'] is List, '策略组 proxies 必须是列表');
      if (kind == GroupKind.select) {
        requireConfig(
          !['url', 'interval', 'tolerance', 'lazy'].any(m.containsKey),
          'select 策略组不支持健康检查字段',
        );
      } else {
        requireConfig(
          m['lazy'] == false,
          '当前内核自动策略组需要显式 lazy: false；惰性测速尚未完整支持',
        );
        requireConfig(m['url'] is String, '自动策略组需要健康检查 URL');
      }
      requireConfig(
        !m.containsKey('interval') || m['interval'] is int,
        'interval 必须是整数',
      );
      requireConfig(
        !m.containsKey('tolerance') || m['tolerance'] is int,
        'tolerance 必须是整数',
      );
      final members = (m['proxies'] as List).map(resolve).toList();
      groups.add(
        PolicyGroup(
          id: names[m['name']]!,
          displayName: m['name'] as String,
          kind: kind,
          members: members,
          selectedId: kind == GroupKind.select ? members.firstOrNull : null,
          url: m['url'] as String?,
          interval: m['interval'] as int? ?? 300,
          tolerance: m['tolerance'] as int? ?? 0,
        ),
      );
    }
    final rules = <RuleSpec>[];
    var finalTarget = proxyTarget;
    if (document.containsKey('rules')) {
      final raw = document['rules'];
      requireConfig(
        raw is List && raw.isNotEmpty && raw.length <= 4096,
        'rules 必须为 1–4096 条规则',
      );
      var matched = false;
      for (var i = 0; i < (raw as List).length; i++) {
        requireConfig(raw[i] is String, '规则必须是字符串');
        final fields = (raw[i] as String)
            .split(',')
            .map((v) => v.trim())
            .toList();
        if (fields.first == 'MATCH') {
          requireConfig(
            fields.length == 2 && i == raw.length - 1,
            'MATCH 必须唯一且位于末尾',
          );
          finalTarget = resolve(fields[1]);
          matched = true;
          continue;
        }
        requireConfig(
          fields.length == 3 ||
              (fields.length == 4 && fields[3] == 'no-resolve'),
          '规则字段数量或修饰符无效',
        );
        final kind = switch (fields.first) {
          'DOMAIN' => RuleKind.domain,
          'DOMAIN-SUFFIX' => RuleKind.domainSuffix,
          'DOMAIN-KEYWORD' => RuleKind.domainKeyword,
          'IP-CIDR' || 'IP-CIDR6' => RuleKind.ipCidr,
          'NETWORK' => RuleKind.network,
          'DST-PORT' => RuleKind.destinationPort,
          _ => throw const ConfigurationException(
            '规则类型尚未支持；GEOIP/GEOSITE/RULE-SET 需要完整资源支持',
          ),
        };
        if (fields.first == 'IP-CIDR6') {
          requireConfig(
            InternetAddress.tryParse(fields[1].split('/').first)?.type ==
                InternetAddressType.IPv6,
            'IP-CIDR6 需要 IPv6 网段',
          );
        }
        rules.add(
          RuleSpec(
            id: const Uuid().v4(),
            kind: kind,
            value: fields[1],
            targetId: resolve(fields[2]),
            noResolve: fields.length == 4,
          ),
        );
      }
      requireConfig(matched, '完整规则配置需要显式最终 MATCH');
    } else {
      requireConfig(groups.isEmpty, '包含策略组的配置必须提供显式 rules/MATCH');
    }
    final result = base.copyWith(
      dns: document.containsKey('dns')
          ? DnsOptions.fromJson(document['dns'])
          : const DnsOptions.system(),
      groups: groups,
      rules: rules,
      mode: mode,
      finalTargetId: finalTarget,
    );
    result.validate();
    return result;
  }

  Profile _uris(String text, String name) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final nodes = <ProxyNode>[];
    requireConfig(lines.length <= 256, '节点列表不能超过 256 个节点');
    for (var i = 0; i < lines.length; i++) {
      try {
        nodes.add(parseShareLink(lines[i]));
      } on ConfigurationException catch (e) {
        throw ConfigurationException('第 ${i + 1} 行：${e.message}');
      } catch (_) {
        // URI errors can contain the complete link, including credentials.
        throw ConfigurationException('第 ${i + 1} 行：节点链接语法或编码无效');
      }
    }
    return _nodeProfile(nodes, name);
  }

  Profile _nodeProfile(List<ProxyNode> nodes, String name) {
    requireConfig(nodes.isNotEmpty, '配置没有可用节点');
    final identities = <String>{};
    for (final node in nodes) {
      requireConfig(identities.add(identity(node)), '存在连接参数完全相同的重复节点，无法可靠区分身份');
    }
    final profile = Profile(
      id: const Uuid().v4(),
      displayName: name,
      nodes: nodes,
      rules: [],
      finalTargetId: proxyTarget,
    );
    profile.validate();
    return profile;
  }

  Profile manual(String name, NodeProtocol protocol, String server, int port) =>
      _nodeProfile([
        ProxyNode(
          id: const Uuid().v4(),
          displayName: name,
          protocol: protocol,
          server: server,
          port: port,
        ),
      ], name);

  static String identity(ProxyNode n) => contentHash(
    canonicalJson(<String, dynamic>{
      'protocol': n.protocol.name,
      'server': n.server.toLowerCase(),
      'port': n.port,
      'options': n.options.toJson(),
    }),
  );

  /// Endpoint identity, never a display name. Remap rule references too.
  Profile reconcile(Profile parsed, ConfigurationSource old) {
    final oldIds = <String, String>{};
    final seen = <String>{};
    for (final n in old.profile.nodes) {
      requireConfig(!oldIds.containsKey(identity(n)), '旧配置存在重复节点身份，无法自动更新');
      oldIds[identity(n)] = n.id;
    }
    final ids = <String, String>{};
    for (final n in parsed.nodes) {
      requireConfig(seen.add(identity(n)), '更新包含重复节点身份');
      ids[n.id] = oldIds[identity(n)] ?? const Uuid().v4();
    }
    final previousGroups = {
      for (final g in old.profile.groups) '${g.kind.name}|${g.displayName}': g,
    };
    for (final g in parsed.groups) {
      ids[g.id] = previousGroups['${g.kind.name}|${g.displayName}']?.id ?? g.id;
    }
    String target(String id) => ids[id] ?? id;
    final groups = parsed.groups.map((g) {
      final previous = previousGroups['${g.kind.name}|${g.displayName}'];
      final members = g.members.map(target).toList();
      final selection =
          previous?.selectedId ??
          (g.selectedId == null ? null : target(g.selectedId!));
      requireConfig(
        selection == null || members.contains(selection),
        '更新移除了策略组已选择成员；保留原配置，请先切换组选择',
      );
      return PolicyGroup(
        id: ids[g.id]!,
        displayName: g.displayName,
        kind: g.kind,
        members: members,
        selectedId: selection,
        url: g.url,
        interval: g.interval,
        tolerance: g.tolerance,
      );
    }).toList();
    final result = Profile(
      id: old.profile.id,
      displayName: old.name,
      revision: old.profile.revision + 1,
      mode: parsed.mode,
      dns: parsed.dns,
      finalTargetId: target(parsed.finalTargetId),
      groups: groups,
      nodes: parsed.nodes
          .map(
            (n) => ProxyNode(
              id: ids[n.id]!,
              displayName: n.displayName,
              protocol: n.protocol,
              server: n.server,
              port: n.port,
              options: n.options,
            ),
          )
          .toList(),
      rules: parsed.rules
          .map(
            (r) => RuleSpec(
              id: r.id,
              kind: r.kind,
              value: r.value,
              targetId: target(r.targetId),
              enabled: r.enabled,
              noResolve: r.noResolve,
            ),
          )
          .toList(),
    );
    requireConfig(
      old.selectedNodeId == directTarget ||
          result.nodes.any((n) => n.id == old.selectedNodeId),
      '更新移除了已选择节点；保留原配置，请先选择仍存在的节点或 DIRECT 后重试',
    );
    result.validate();
    return result;
  }
}

class SubscriptionFetcher {
  const SubscriptionFetcher();
  Future<String> fetch(String address) async {
    final uri = Uri.tryParse(address);
    requireConfig(
      uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment,
      '订阅链接无效，仅支持 HTTP(S)，不支持 URL 用户认证或片段',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    // Explicit direct fetch: a stale system proxy must not trap recovery/download.
    client.findProxy = (_) => 'DIRECT';
    try {
      return await (() async {
        final request = await client.getUrl(uri!);
        request.followRedirects = false;
        // Explicit Clash-format negotiation; some subscription servers return
        // 403 or a different format for an unrecognized user agent.
        request.headers.set(HttpHeaders.userAgentHeader, 'clash.meta');
        final response = await request.close();
        requireConfig(
          response.statusCode == 200,
          response.isRedirect
              ? '订阅地址发生重定向，请使用最终下载地址'
              : '订阅服务器返回 HTTP ${response.statusCode}',
        );
        requireConfig(response.contentLength <= maxImportBytes, '订阅超过 1 MiB');
        final bytes = <int>[];
        await for (final chunk in response) {
          requireConfig(
            bytes.length + chunk.length <= maxImportBytes,
            '订阅超过 1 MiB',
          );
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 20));
    } on ConfigurationException {
      rethrow;
    } catch (_) {
      throw const ConfigurationException('订阅下载失败：请检查网络、地址、证书和 UTF-8 编码');
    } finally {
      client.close(force: true);
    }
  }
}
