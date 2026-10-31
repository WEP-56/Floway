part of 'profile.dart';

/// Ordinary-proxy resolver configuration. No OS DNS settings, DNS listener,
/// Fake-IP pool or routing of DNS through proxy groups is implied.
class DnsOptions {
  const DnsOptions.system()
    : enabled = false,
      nameservers = const [],
      fallbacks = const [],
      filter = null;

  DnsOptions({
    required List<String> nameservers,
    List<String> fallbacks = const [],
    this.filter,
  }) : enabled = true,
       nameservers = List.unmodifiable(nameservers),
       fallbacks = List.unmodifiable(fallbacks);

  final bool enabled;
  final List<String> nameservers, fallbacks;
  final DnsFallbackFilter? filter;

  void validate() {
    if (!enabled) return;
    requireConfig(nameservers.isNotEmpty, '自定义 DNS 需要至少一个 nameserver');
    for (final list in [nameservers, fallbacks]) {
      requireConfig(
        list.length <= 16 && list.toSet().length == list.length,
        'DNS 上游重复或超过 16 个',
      );
      for (final server in list) {
        _validateDnsServer(server);
      }
    }
    requireConfig(
      filter == null || fallbacks.isNotEmpty,
      'fallback-filter 需要 fallback 上游',
    );
    filter?.validate();
  }

  Map<String, Object?> toJson() => {
    'enable': enabled,
    if (enabled) ...{
      'ipv6': false,
      'enhanced-mode': 'redir-host',
      'nameserver': nameservers,
      'fallback': fallbacks,
      if (filter != null) 'fallback-filter': filter!.toJson(),
    },
  };

  Map<String, Object?> toRuntimeJson() => {
    ...toJson(),
    if (enabled) ...{
      // vp-config rejects bare IP:port although the resolver accepts it.
      // Use an explicit transport rather than widening upstream validation.
      'nameserver': [
        for (final s in nameservers) s.contains('://') ? s : 'udp://$s',
      ],
      'fallback': [
        for (final s in fallbacks) s.contains('://') ? s : 'udp://$s',
      ],
    },
  };

  factory DnsOptions.fromJson(Object? value) {
    final m = jsonObject(value, {
      'enable',
      'ipv6',
      'enhanced-mode',
      'nameserver',
      'fallback',
      'fallback-filter',
    }, 'DNS（Fake-IP、listen、respect-rules、default-nameserver、policy 尚未支持）');
    requireConfig(m['enable'] is bool, 'DNS enable 必须是布尔值');
    if (m['enable'] == false) {
      requireConfig(m.length == 1, '关闭 DNS 时不能携带会被忽略的自定义字段');
      return const DnsOptions.system();
    }
    requireConfig(
      !m.containsKey('ipv6') || m['ipv6'] == false,
      '当前 DNS 仅支持 IPv4 查询（ipv6: false）',
    );
    requireConfig(
      !m.containsKey('enhanced-mode') || m['enhanced-mode'] == 'redir-host',
      '当前普通代理 DNS 仅支持 redir-host，尚不支持 Fake-IP',
    );
    List<String> strings(String key) {
      final v = m[key] ?? (key == 'fallback' ? <String>[] : null);
      requireConfig(v is List && v.every((s) => s is String), 'DNS 上游必须为字符串列表');
      return List<String>.from(v as List);
    }

    requireConfig(
      !m.containsKey('fallback') || m['fallback'] != null,
      'fallback 不能为 null',
    );
    final result = DnsOptions(
      nameservers: strings('nameserver'),
      fallbacks: strings('fallback'),
      filter: m.containsKey('fallback-filter')
          ? DnsFallbackFilter.fromJson(m['fallback-filter'])
          : null,
    );
    result.validate();
    return result;
  }
}

class DnsFallbackFilter {
  DnsFallbackFilter({
    List<String> cidrs = const [],
    List<String> domains = const [],
  }) : cidrs = List.unmodifiable(cidrs),
       domains = List.unmodifiable(domains);
  final List<String> cidrs, domains;

  void validate() {
    requireConfig(
      cidrs.length <= 64 &&
          domains.length <= 64 &&
          cidrs.toSet().length == cidrs.length &&
          domains.toSet().length == domains.length,
      'DNS fallback 过滤条件重复或过多',
    );
    for (final cidr in cidrs) {
      final parts = cidr.split('/');
      final address = InternetAddress.tryParse(parts.first);
      final prefix = parts.length == 2 ? int.tryParse(parts.last) : null;
      requireConfig(
        address != null &&
            prefix != null &&
            prefix >= 0 &&
            prefix <= (address.type == InternetAddressType.IPv4 ? 32 : 128),
        'DNS fallback CIDR 无效',
      );
    }
    for (final domain in domains) {
      requireConfig(
        domain.startsWith('+.') && _dnsHost(domain.substring(2)),
        'DNS fallback domain 当前仅支持 +.域名 后缀格式',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'geoip': false,
    'ipcidr': cidrs,
    'domain': domains,
  };

  factory DnsFallbackFilter.fromJson(Object? value) {
    final m = jsonObject(value, {
      'geoip',
      'ipcidr',
      'domain',
    }, 'DNS fallback-filter');
    requireConfig(
      m['geoip'] == false,
      'DNS fallback-filter 需要显式 geoip: false；Geo 资源尚未接入',
    );
    List<String> strings(String key) {
      final v = m.containsKey(key) ? m[key] : <String>[];
      requireConfig(
        v is List && v.every((s) => s is String),
        'DNS fallback 过滤条件必须为字符串列表',
      );
      return List<String>.from(v as List);
    }

    final result = DnsFallbackFilter(
      cidrs: strings('ipcidr'),
      domains: strings('domain'),
    );
    result.validate();
    return result;
  }
}

bool _dnsHost(String host) =>
    host.length <= 253 &&
    host.isNotEmpty &&
    host
        .split('.')
        .every(
          (label) =>
              label.length <= 63 &&
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                  .hasMatch(label),
        );

void _validateDnsServer(String server) {
  const error =
      'DNS 上游格式不受支持（UDP/TCP/DoT 仅 IPv4，DoH 为 HTTPS 且无 query/fragment）';
  requireConfig(
    server.isNotEmpty &&
        server.length <= 2048 &&
        !RegExp(r'[\x00-\x20\x7f-\uffff]').hasMatch(server) &&
        !server.contains('\\'),
    error,
  );
  requireConfig(
    !server.contains('://') ||
        ['udp', 'tcp', 'tls', 'https'].contains(server.split('://').first),
    error,
  );
  final authority = (server.contains('://') ? server.split('://').last : server)
      .split('/')
      .first;
  requireConfig(!authority.endsWith(':') && !authority.contains('%'), error);
  final uri = Uri.tryParse(server.contains('://') ? server : 'udp://$server');
  if (uri == null) throw const ConfigurationException(error);
  requireConfig(
    ['udp', 'tcp', 'tls', 'https'].contains(uri.scheme) &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        !uri.authority.contains('%'),
    error,
  );
  final portFields = authority.split(':');
  requireConfig(
    portFields.length <= 2 &&
        (portFields.length == 1 || RegExp(r'^\d+$').hasMatch(portFields.last)),
    error,
  );
  final port = portFields.length == 2
      ? int.tryParse(portFields.last) ?? 0
      : switch (uri.scheme) {
          'https' => 443,
          'tls' => 853,
          _ => 53,
        };
  requireConfig(port >= 1 && port <= 65535 && _dnsHost(uri.host), error);
  if (uri.scheme == 'https') {
    requireConfig(uri.path.isEmpty || uri.path.startsWith('/'), error);
  } else {
    requireConfig(
      uri.path.isEmpty &&
          InternetAddress.tryParse(uri.host)?.type == InternetAddressType.IPv4,
      error,
    );
  }
  // Do not allow a malformed explicit port to be normalized to a default.
  requireConfig(!uri.authority.endsWith(':'), error);
}
