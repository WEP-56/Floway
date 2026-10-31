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
  Profile parse(String text, {required String name, List<String>? warnings}) {
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
      requireConfig(yaml is Map, 'Clash 配置必须是对象');
      // 真实订阅普遍携带 TUN、sniffer、profile 等顶层字段。单个未接入字段
      // 不应让整份配置失败，改为逐字段提示并只降级该字段。
      const supportedTop = {
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
        'tun',
        'rule-providers',
      };
      for (final key in (yaml as Map).keys) {
        final field = '$key';
        if (!supportedTop.contains(field)) {
          warnings?.add('顶层字段 $field 暂未接入，已忽略');
        }
      }
      final proxies = yaml['proxies'];
      requireConfig(
        proxies is List && proxies.isNotEmpty,
        'Clash proxies 必须为非空节点列表',
      );
      final nodes = <ProxyNode>[];
      for (var i = 0; i < (proxies as List).length; i++) {
        final item = proxies[i];
        try {
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
        const tlsImplied = {
          NodeProtocol.trojan,
          NodeProtocol.anytls,
          NodeProtocol.hysteria,
          NodeProtocol.hysteria2,
        };
        if (parameters['tls'] != true && !tlsImplied.contains(protocol)) {
          // 未启用 TLS 时 sni/alpn 不生效，Clash 也只会在 TLS 下使用它们。
          for (final key in [
            'sni',
            'alpn',
            'client-fingerprint',
            'skip-cert-verify',
            'reality-opts',
          ]) {
            parameters.remove(key);
          }
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
        final node = ProxyNode(
          id: const Uuid().v4(),
          displayName: item['name'] as String,
          protocol: protocol,
          server: item['server'] as String,
          port: item['port'] as int,
          options: NodeOptions.fromJson(
            parameters,
            warn: warnings?.add,
            protocol: protocol,
          ),
        );
        node.validate();
        nodes.add(node);
        } on ConfigurationException catch (error) {
          final label = item is Map && item['name'] is String
              ? item['name'] as String
              : '第 ${i + 1} 个节点';
          warnings?.add('节点 $label 已跳过：${error.message}');
        }
      }
      requireConfig(nodes.isNotEmpty, '没有可导入的节点；所有节点的协议或参数暂未支持');
      if (nodes.length > 1024) {
        warnings?.add('节点数 ${nodes.length} 超过上限，仅导入前 1024 个');
        nodes.removeRange(1024, nodes.length);
      }
      final profile = _nodeProfile(nodes, name);
      return _clashPolicy(
        jsonDecode(jsonEncode(yaml)) as Map<String, dynamic>,
        profile,
        warnings: warnings,
      );
    } on ConfigurationException {
      rethrow;
    } catch (_) {
      // Parser exceptions often contain source lines or credentials.
      throw const ConfigurationException('配置语法或编码无效；未导入任何节点');
    }
  }

  /// DNS 开启但缺少 nameserver 在真实订阅里很常见，降级为系统 DNS。
  DnsOptions _dnsFrom(Object? value, List<String>? warnings) {
    if (value == null) return const DnsOptions.system();
    if (value is Map) {
      final nameservers = value['nameserver'];
      final enabled = value['enable'] != false;
      if (enabled && (nameservers is! List || nameservers.isEmpty)) {
        warnings?.add('DNS 未提供 nameserver，已回退系统 DNS');
        final copy = Map<String, Object?>.from(value);
        copy['enable'] = false;
        return DnsOptions.fromJson(copy, warn: warnings?.add);
      }
    }
    return DnsOptions.fromJson(value, warn: warnings?.add);
  }

  Profile _clashPolicy(
    Map<String, dynamic> document,
    Profile base, {
    List<String>? warnings,
  }) {
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
    // 订阅里常见大写 Rule/Global，按不区分大小写处理。
    final modeValue = document['mode'];
    RoutingMode mode = RoutingMode.rule;
    if (modeValue != null) {
      final text = '$modeValue'.trim().toLowerCase();
      final found = RoutingMode.values.where((m) => m.name == text).firstOrNull;
      if (found == null) {
        warnings?.add('模式 $modeValue 暂未接入，已按 rule 处理');
      } else {
        mode = found;
      }
    }
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
    const groupKeys = {
      'name',
      'type',
      'proxies',
      'url',
      'interval',
      'tolerance',
      'lazy',
    };
    final maps = <Map<String, dynamic>>[];
    for (final item in groupData as List) {
      if (item is! Map) {
        warnings?.add('策略组必须是对象，已跳过一项');
        continue;
      }
      final m = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(item)) as Map<String, dynamic>,
      );
      for (final key in m.keys.toList()) {
        if (!groupKeys.contains(key)) {
          warnings?.add('策略组 ${m['name']} 字段 $key 暂未接入，已忽略');
          m.remove(key);
        }
      }
      if (m['name'] is! String) {
        warnings?.add('策略组缺少 name，已跳过一项');
        continue;
      }
      final name = m['name'] as String;
      if (names.containsKey(name)) {
        warnings?.add('策略组名称 $name 与已有名称重复，已跳过');
        continue;
      }
      names[name] = const Uuid().v4();
      maps.add(m);
    }
    String? resolveOrNull(Object? name) => name is String ? names[name] : null;

    final groups = <PolicyGroup>[];
    for (final m in maps) {
      final groupName = m['name'] as String;
      final kind = switch (m['type']) {
        'select' => GroupKind.select,
        'url-test' => GroupKind.urlTest,
        'fallback' => GroupKind.fallback,
        _ => null,
      };
      if (kind == null) {
        warnings?.add('策略组 $groupName 类型 ${m['type']} 暂未接入，已跳过');
        names.remove(groupName);
        continue;
      }
      if (m['proxies'] is! List) {
        warnings?.add('策略组 $groupName 缺少 proxies，已跳过');
        names.remove(groupName);
        continue;
      }
      if (kind == GroupKind.select &&
          ['url', 'interval', 'tolerance', 'lazy'].any(m.containsKey)) {
        warnings?.add('策略组 $groupName 为 select，健康检查字段已忽略');
      }
      if (kind != GroupKind.select && m['lazy'] == true) {
        warnings?.add('策略组 $groupName 的 lazy 暂未接入，已按立即测速');
      }
      var interval = m['interval'] is int ? m['interval'] as int : 300;
      if (interval < 60) {
        warnings?.add('策略组 $groupName 的 interval 过小，已调整为 60');
        interval = 60;
      }
      var tolerance = m['tolerance'] is int ? m['tolerance'] as int : 0;
      if (tolerance < 0) {
        warnings?.add('策略组 $groupName 的 tolerance 无效，已调整为 0');
        tolerance = 0;
      }
      var healthUrl = m['url'] is String ? m['url'] as String : null;
      if (kind != GroupKind.select) {
        final uri = healthUrl == null ? null : Uri.tryParse(healthUrl);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.userInfo.isNotEmpty) {
          warnings?.add('策略组 $groupName 的健康检查 URL 无效，已使用默认地址');
          healthUrl = 'https://www.gstatic.com/generate_204';
        }
      }
      final members = <String>[];
      for (final target in m['proxies'] as List) {
        final id = target is String ? names[target] : null;
        if (id == null) {
          warnings?.add('策略组 $groupName 引用了未导入的 ${target ?? 'null'}，已移除');
          continue;
        }
        if (members.contains(id)) {
          warnings?.add('策略组 $groupName 存在重复成员，已去重');
          continue;
        }
        members.add(id);
      }
      if (members.isEmpty) {
        warnings?.add('策略组 $groupName 没有可用成员，已跳过');
        names.remove(groupName);
        continue;
      }
      groups.add(
        PolicyGroup(
          id: names[groupName]!,
          displayName: groupName,
          kind: kind,
          members: members,
          selectedId: kind == GroupKind.select ? members.firstOrNull : null,
          url: healthUrl,
          interval: interval,
          tolerance: tolerance,
        ),
      );
    }
    // 被跳过的策略组可能已被其他组引用，这里再做一次引用清理。
    final validTargets = {
      directTarget,
      rejectTarget,
      ...base.nodes.map((node) => node.id),
      ...groups.map((group) => group.id),
    };
    final cleaned = <PolicyGroup>[];
    for (final group in groups) {
      final members = group.members.where(validTargets.contains).toList();
      if (members.isEmpty) {
        warnings?.add('策略组 ${group.displayName} 没有可用成员，已跳过');
        continue;
      }
      final selected = group.selectedId != null && members.contains(group.selectedId)
          ? group.selectedId
          : (group.kind == GroupKind.select ? members.first : null);
      cleaned.add(
        PolicyGroup(
          id: group.id,
          displayName: group.displayName,
          kind: group.kind,
          members: members,
          selectedId: selected,
          url: group.url,
          interval: group.interval,
          tolerance: group.tolerance,
        ),
      );
    }
    groups
      ..clear()
      ..addAll(cleaned);
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
          finalTarget = resolveOrNull(fields[1]) ?? proxyTarget;
          if (resolveOrNull(fields[1]) == null) {
            warnings?.add('MATCH 目标 ${fields[1]} 未导入，已回退到首个节点');
          }
          matched = true;
          continue;
        }
        final kind = switch (fields.first) {
          'DOMAIN' => RuleKind.domain,
          'DOMAIN-SUFFIX' => RuleKind.domainSuffix,
          'DOMAIN-KEYWORD' => RuleKind.domainKeyword,
          'IP-CIDR' || 'IP-CIDR6' => RuleKind.ipCidr,
          'NETWORK' => RuleKind.network,
          'DST-PORT' => RuleKind.destinationPort,
          'GEOIP' => RuleKind.geoIp,
          'GEOSITE' => RuleKind.geoSite,
          'RULE-SET' => RuleKind.ruleSet,
          _ => null,
        };
        if (kind == null) {
          warnings?.add('规则类型 ${fields.first} 暂未接入，已跳过：${raw[i]}');
          continue;
        }
        requireConfig(
          fields.length == 3 ||
              (fields.length == 4 && fields[3] == 'no-resolve'),
          '规则字段数量或修饰符无效',
        );
        if (fields.first == 'RULE-SET') {
          final providers = document['rule-providers'];
          requireConfig(
            providers is Map && providers.containsKey(fields[1]),
            '规则集 ${fields[1]} 未在 rule-providers 中定义',
          );
        }
        if (fields.first == 'IP-CIDR6') {
          requireConfig(
            InternetAddress.tryParse(fields[1].split('/').first)?.type ==
                InternetAddressType.IPv6,
            'IP-CIDR6 需要 IPv6 网段',
          );
        }
        final targetId = resolveOrNull(fields[2]);
        if (targetId == null) {
          warnings?.add('规则目标 ${fields[2]} 未导入，已跳过：${raw[i]}');
          continue;
        }
        rules.add(
          RuleSpec(
            id: const Uuid().v4(),
            kind: kind,
            value: fields.first == 'GEOIP'
                ? fields[1].toUpperCase()
                : fields[1],
            targetId: targetId,
            noResolve: fields.length == 4,
          ),
        );
      }
      if (!matched) {
        warnings?.add('规则缺少最终 MATCH，未命中流量按首个节点处理');
      }
    } else {
      requireConfig(groups.isEmpty, '包含策略组的配置必须提供显式 rules/MATCH');
    }
    final result = base.copyWith(
      dns: _dnsFrom(document['dns'], warnings),
      tun: TunOptions.fromClash(document['tun'], warn: warnings?.add),
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
    // 真实订阅常出现同端点多名称、或同名多节点：端点允许重复，名称去重。
    final used = <String>{};
    final unique = <ProxyNode>[];
    for (final node in nodes) {
      var display = node.displayName;
      var suffix = 2;
      while (!used.add(display)) {
        display = '${node.displayName} #$suffix';
        suffix += 1;
      }
      unique.add(
        display == node.displayName
            ? node
            : ProxyNode(
                id: node.id,
                displayName: display,
                protocol: node.protocol,
                server: node.server,
                port: node.port,
                options: node.options,
              ),
      );
    }
    nodes = unique;
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
    // 同一端点多条目是常态：按身份分组，优先同名，再按出现顺序配对。
    final oldByKey = <String, List<ProxyNode>>{};
    for (final n in old.profile.nodes) {
      oldByKey.putIfAbsent(identity(n), () => <ProxyNode>[]).add(n);
    }
    final usedOld = <String>{};
    final ids = <String, String>{};
    for (final n in parsed.nodes) {
      final candidates = oldByKey[identity(n)];
      String? matched;
      if (candidates != null) {
        for (final candidate in candidates) {
          if (!usedOld.contains(candidate.id) &&
              candidate.displayName == n.displayName) {
            matched = candidate.id;
            break;
          }
        }
        matched ??= candidates
            .where((candidate) => !usedOld.contains(candidate.id))
            .firstOrNull
            ?.id;
      }
      final id = matched ?? const Uuid().v4();
      usedOld.add(id);
      ids[n.id] = id;
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
      tun: parsed.tun,
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
