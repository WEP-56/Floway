part of 'profile.dart';

/// TUN 选项：字段与内核 TunCfg 对齐；Clash 中常见但内核没有的字段
/// （stack、dns-hijack 等）在导入时单独提示并忽略，不拖垮整份配置。
class TunOptions {
  const TunOptions.disabled()
    : enabled = false,
      autoRoute = false,
      mtu = 1500,
      address = '198.18.0.1',
      netmask = '255.255.0.0',
      fakeIpRange = '198.18.0.0/16';

  const TunOptions({
    required this.enabled,
    this.autoRoute = true,
    this.mtu = 1500,
    this.address = '198.18.0.1',
    this.netmask = '255.255.0.0',
    this.fakeIpRange = '198.18.0.0/16',
  });

  static const stackIgnored = {
    'stack',
    'dns-hijack',
    'auto-detect-interface',
    'strict-route',
    'device',
    'gso',
    'udp-timeout',
    'endpoint-independent-nat',
  };

  final bool enabled;
  final bool autoRoute;
  final int mtu;
  final String address;
  final String netmask;
  final String fakeIpRange;

  TunOptions copyWith({bool? enabled, bool? autoRoute, int? mtu}) => TunOptions(
    enabled: enabled ?? this.enabled,
    autoRoute: autoRoute ?? this.autoRoute,
    mtu: mtu ?? this.mtu,
    address: address,
    netmask: netmask,
    fakeIpRange: fakeIpRange,
  );

  static final _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  void validate() {
    requireConfig(mtu >= 576 && mtu <= 9000, 'TUN MTU 必须在 576-9000');
    requireConfig(_ipv4.hasMatch(address), 'TUN 地址必须是 IPv4');
    requireConfig(_ipv4.hasMatch(netmask), 'TUN 掩码必须是 IPv4');
    final range = fakeIpRange.split('/');
    requireConfig(
      range.length == 2 &&
          _ipv4.hasMatch(range.first) &&
          int.tryParse(range.last) != null,
      'fake-ip-range 必须是 CIDR',
    );
  }

  Map<String, Object?> toRuntimeJson() => {
    'enable': enabled,
    'auto-route': autoRoute,
    'mtu': mtu,
    'address': address,
    'netmask': netmask,
    'fake-ip-range': fakeIpRange,
  };

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'autoRoute': autoRoute,
    'mtu': mtu,
    'address': address,
    'netmask': netmask,
    'fakeIpRange': fakeIpRange,
  };

  factory TunOptions.fromJson(Object? value) {
    final map = jsonObject(value, {
      'enabled',
      'autoRoute',
      'mtu',
      'address',
      'netmask',
      'fakeIpRange',
    }, 'tun');
    requireConfig(
      map['enabled'] is bool &&
          map['autoRoute'] is bool &&
          map['mtu'] is int &&
          map['address'] is String &&
          map['netmask'] is String &&
          map['fakeIpRange'] is String,
      'tun 字段类型无效',
    );
    final options = TunOptions(
      enabled: map['enabled'] as bool,
      autoRoute: map['autoRoute'] as bool,
      mtu: map['mtu'] as int,
      address: map['address'] as String,
      netmask: map['netmask'] as String,
      fakeIpRange: map['fakeIpRange'] as String,
    );
    options.validate();
    return options;
  }

  /// 从 Clash/mihomo 的 tun 段读取；未支持字段逐个提示并忽略。
  factory TunOptions.fromClash(Object? value, {void Function(String)? warn}) {
    if (value == null) return const TunOptions.disabled();
    requireConfig(value is Map, 'tun 必须是对象');
    final map = Map<String, dynamic>.from(value as Map);
    for (final key in map.keys.toList()) {
      if (const {
        'enable',
        'auto-route',
        'mtu',
        'address',
        'netmask',
        'fake-ip-range',
      }.contains(key)) {
        continue;
      }
      if (stackIgnored.contains(key)) {
        warn?.call('tun 字段 $key 暂未接入，已忽略');
        map.remove(key);
        continue;
      }
      warn?.call('tun 字段 $key 不受支持，已忽略');
      map.remove(key);
    }
    bool flag(String key, bool fallback) => switch (map[key]) {
      bool value => value,
      null => fallback,
      _ => fallback,
    };
    final mtu = switch (map['mtu']) {
      int value when value >= 576 && value <= 9000 => value,
      null => 1500,
      _ => 1500,
    };
    if (map.containsKey('mtu') && mtu == 1500 && map['mtu'] != 1500) {
      warn?.call('tun 字段 mtu 无效，已回退为 1500');
    }
    String text(String key, String fallback) {
      final candidate = map[key];
      if (candidate is String && candidate.isNotEmpty) return candidate;
      if (candidate != null) warn?.call('tun 字段 $key 无效，已回退为 $fallback');
      return fallback;
    }

    final options = TunOptions(
      enabled: flag('enable', false),
      autoRoute: flag('auto-route', true),
      mtu: mtu,
      address: text('address', '198.18.0.1'),
      netmask: text('netmask', '255.255.0.0'),
      fakeIpRange: text('fake-ip-range', '198.18.0.0/16'),
    );
    return options;
  }
}
