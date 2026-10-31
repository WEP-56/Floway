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

  /// TUN 模式下必须走 fake-ip。
  ///
  /// 内核的 `auto-route` 只把 fake-IP 网段（默认 198.18.0.0/16）路由进隧道，
  /// 不做全流量接管。域名必须先解析成 fake-IP 才会进入代理；用 redir-host
  /// 拿到的是真实 IP，流量走物理网卡，出口仍是本机 IP。
  ///
  /// [fakeIpRange] 非空表示当前处于 TUN 模式；此时若用户没配上游，用国内
  /// 公共 DNS 兜底，否则内核解析器没有可用上游。
  Map<String, Object?> toRuntimeJson({String? fakeIpRange}) {
    final tun = fakeIpRange != null;
    final upstreams = enabled && nameservers.isNotEmpty
        ? nameservers
        : tun
        ? _defaultTunNameservers
        : const <String>[];
    return {
      ...toJson(),
      if (tun) ...{
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'fake-ip-range': fakeIpRange,
      },
      if (upstreams.isNotEmpty) ...{
        // vp-config rejects bare IP:port although the resolver accepts it.
        // Use an explicit transport rather than widening upstream validation.
        'nameserver': [
          for (final s in upstreams) s.contains('://') ? s : 'udp://$s',
        ],
        'fallback': [
          for (final s in fallbacks) s.contains('://') ? s : 'udp://$s',
        ],
      },
    };
  }

  /// TUN 模式且用户未配置上游时的兜底解析器。
  static const _defaultTunNameservers = ['223.5.5.5', '119.29.29.29'];

  factory DnsOptions.fromJson(Object? value, {void Function(String)? warn}) {
    requireConfig(value is Map, 'DNS 必须是对象');
    final m = Map<String, Object?>.from(value as Map);
    const known = {
      'enable',
      'ipv6',
      'enhanced-mode',
      'nameserver',
      'fallback',
      'fallback-filter',
    };
    for (final key in m.keys.toList()) {
      if (!known.contains(key)) {
        warn?.call('DNS 字段 $key 暂未接入，已忽略');
        m.remove(key);
      }
    }
    requireConfig(m['enable'] is bool, 'DNS enable 必须是布尔值');
    if (m['enable'] == false) {
      return const DnsOptions.system();
    }
    if (m['ipv6'] == true) {
      warn?.call('DNS ipv6: true 暂未接入，已按 IPv4 查询处理');
    }
    final enhanced = m['enhanced-mode'];
    // fake-ip 只在 TUN 模式下有意义，且由 tun.fake-ip-range 统一决定池网段；
    // 订阅里自带的 fake-ip-range 不采信，避免与 TUN 网段不一致。
    if (enhanced != null && enhanced != 'redir-host' && enhanced != 'fake-ip') {
      warn?.call('DNS enhanced-mode $enhanced 暂未接入，已按 redir-host 处理');
    }
    if (enhanced == 'fake-ip') {
      warn?.call('DNS fake-ip 由 TUN 模式自动启用，订阅内的池网段已忽略');
    }
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
          ? DnsFallbackFilter.fromJson(m['fallback-filter'], warn: warn)
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

  factory DnsFallbackFilter.fromJson(
    Object? value, {
    void Function(String)? warn,
  }) {
    requireConfig(value is Map, 'DNS fallback-filter 必须是对象');
    final m = Map<String, Object?>.from(value as Map);
    const known = {'geoip', 'ipcidr', 'domain'};
    for (final key in m.keys.toList()) {
      if (!known.contains(key)) {
        warn?.call('DNS fallback-filter 字段 $key 暂未接入，已忽略');
        m.remove(key);
      }
    }
    if (m['geoip'] != false) {
      warn?.call('DNS fallback-filter geoip 规则暂未接入，已忽略');
    }
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
