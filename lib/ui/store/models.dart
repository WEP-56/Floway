import '../design/accents.dart';

/// Data models, defaults and label maps mirrored from the design's src/data.ts.

enum FlvpThemeMode { system, light, dark }

enum FlvpLang { zh, en, ja }

enum FlvpProxyMode { rule, global, direct }

enum FlvpCloseBehavior { tray, quit }

enum FlvpStatsScope { total, session }

class NodeInfo {
  const NodeInfo({
    required this.id,
    required this.name,
    required this.sub,
    required this.proto,
    required this.region,
    this.latency,
  });

  final String id;
  final String name;
  final String sub;
  final String proto;
  final String region;
  final int? latency;

  NodeInfo withLatency(int? value) => NodeInfo(
    id: id,
    name: name,
    sub: sub,
    proto: proto,
    region: region,
    latency: value,
  );
}

class SubInfo {
  const SubInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.used,
    required this.total,
    required this.expire,
    required this.updated,
    required this.active,
  });

  final String id;
  final String name;
  final String url;
  final double used;
  final double total;
  final String expire;
  final String updated;
  final bool active;

  SubInfo copyWith({double? used, double? total, String? updated, bool? active}) =>
      SubInfo(
        id: id,
        name: name,
        url: url,
        used: used ?? this.used,
        total: total ?? this.total,
        expire: expire,
        updated: updated ?? this.updated,
        active: active ?? this.active,
      );
}

class AppSettings {
  const AppSettings({
    this.language = FlvpLang.zh,
    this.theme = FlvpThemeMode.light,
    this.accent = FlvpAccent.indigo,
    this.mode = FlvpProxyMode.rule,
    this.autoStart = true,
    this.silentStart = true,
    this.autoConnect = true,
    this.closeBehavior = FlvpCloseBehavior.tray,
    this.statsScope = FlvpStatsScope.total,
    this.mixedPort = '7890',
    this.socksPort = '7891',
    this.allowLan = false,
    this.systemProxy = true,
    this.tunMode = false,
    this.dns = 'https://dns.alidns.com/dns-query',
    this.sniff = true,
    this.ipv6 = false,
    this.logLevel = 'info',
    this.stack = 'mixed',
  });

  final FlvpLang language;
  final FlvpThemeMode theme;
  final FlvpAccent accent;
  final FlvpProxyMode mode;
  final bool autoStart;
  final bool silentStart;
  final bool autoConnect;
  final FlvpCloseBehavior closeBehavior;
  final FlvpStatsScope statsScope;
  final String mixedPort;
  final String socksPort;
  final bool allowLan;
  final bool systemProxy;
  final bool tunMode;
  final String dns;
  final bool sniff;
  final bool ipv6;
  final String logLevel;
  final String stack;

  AppSettings copyWith({
    FlvpLang? language,
    FlvpThemeMode? theme,
    FlvpAccent? accent,
    FlvpProxyMode? mode,
    bool? autoStart,
    bool? silentStart,
    bool? autoConnect,
    FlvpCloseBehavior? closeBehavior,
    FlvpStatsScope? statsScope,
    String? mixedPort,
    String? socksPort,
    bool? allowLan,
    bool? systemProxy,
    bool? tunMode,
    String? dns,
    bool? sniff,
    bool? ipv6,
    String? logLevel,
    String? stack,
  }) => AppSettings(
    language: language ?? this.language,
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    mode: mode ?? this.mode,
    autoStart: autoStart ?? this.autoStart,
    silentStart: silentStart ?? this.silentStart,
    autoConnect: autoConnect ?? this.autoConnect,
    closeBehavior: closeBehavior ?? this.closeBehavior,
    statsScope: statsScope ?? this.statsScope,
    mixedPort: mixedPort ?? this.mixedPort,
    socksPort: socksPort ?? this.socksPort,
    allowLan: allowLan ?? this.allowLan,
    systemProxy: systemProxy ?? this.systemProxy,
    tunMode: tunMode ?? this.tunMode,
    dns: dns ?? this.dns,
    sniff: sniff ?? this.sniff,
    ipv6: ipv6 ?? this.ipv6,
    logLevel: logLevel ?? this.logLevel,
    stack: stack ?? this.stack,
  );
}

const flvpAppVersion = '0.1.0';
const flvpCoreVersion = 'vp_core 1.1.0 + P001';
const flvpBuildDate = '2026-10-30';

const List<NodeInfo> flvpInitialNodes = [
  NodeInfo(id: 'auto', name: '自动选择', sub: '策略组', proto: '延迟最低优先', region: '', latency: 42),
  NodeInfo(id: 'hk-01', name: '香港 01', sub: 'FLVP 高级订阅', proto: 'Hysteria2', region: 'HK', latency: 42),
  NodeInfo(id: 'hk-02', name: '香港 02', sub: 'FLVP 高级订阅', proto: 'Hysteria2', region: 'HK', latency: 58),
  NodeInfo(id: 'jp-01', name: '东京 01', sub: 'FLVP 高级订阅', proto: 'VLESS', region: 'JP', latency: 86),
  NodeInfo(id: 'tw-01', name: '台北 01', sub: 'FLVP 高级订阅', proto: 'Shadowsocks', region: 'TW', latency: 97),
  NodeInfo(id: 'sg-01', name: '新加坡 01', sub: 'FLVP 高级订阅', proto: 'Trojan', region: 'SG', latency: 121),
  NodeInfo(id: 'us-01', name: '洛杉矶 01', sub: 'FLVP 高级订阅', proto: 'VLESS', region: 'US', latency: 168),
  NodeInfo(id: 'home', name: '家庭网关', sub: '自建节点', proto: 'VMess', region: '', latency: 8),
  NodeInfo(id: 'office', name: '办公室', sub: '自建节点', proto: 'VMess', region: '', latency: 24),
];

const List<SubInfo> flvpInitialSubs = [
  SubInfo(
    id: 's1',
    name: 'FLVP 高级订阅',
    url: 'https://api.flvp.io/v1/subscribe?token=8f2a91c7d4',
    used: 42.6,
    total: 200,
    expire: '2027-08-14',
    updated: '3 分钟前',
    active: true,
  ),
  SubInfo(
    id: 's2',
    name: '备用订阅',
    url: 'https://cdn.flvp.net/clash/config?key=b71d30',
    used: 8.2,
    total: 50,
    expire: '2027-03-01',
    updated: '昨天 21:07',
    active: false,
  ),
  SubInfo(
    id: 's3',
    name: '免费节点池',
    url: 'https://free.flvp.io/airport/list',
    used: 118.4,
    total: 150,
    expire: '2026-11-20',
    updated: '6 天前',
    active: false,
  ),
];

/// Placeholder so views never crash when every subscription was removed.
const flvpEmptySub = SubInfo(
  id: 'none',
  name: '未导入订阅',
  url: '',
  used: 0,
  total: 0,
  expire: '—',
  updated: '—',
  active: true,
);

class FlvpShortcut {
  const FlvpShortcut(this.keys, this.description);
  final List<String> keys;
  final String description;
}

const List<FlvpShortcut> flvpShortcuts = [
  FlvpShortcut(['Ctrl', 'Shift', 'F'], '显示 / 隐藏主窗口'),
  FlvpShortcut(['Ctrl', 'Shift', 'P'], '开启 / 停止代理'),
  FlvpShortcut(['Ctrl', 'Shift', 'N'], '切换到下一个节点'),
  FlvpShortcut(['Ctrl', 'Shift', 'S'], '切换系统代理'),
  FlvpShortcut(['Ctrl', 'Shift', 'C'], '复制终端代理命令'),
];

const Map<FlvpLang, String> flvpLanguageLabels = {
  FlvpLang.zh: '简体中文',
  FlvpLang.en: 'English',
  FlvpLang.ja: '日本語',
};

const Map<FlvpThemeMode, String> flvpThemeLabels = {
  FlvpThemeMode.system: '跟随系统',
  FlvpThemeMode.light: '浅色',
  FlvpThemeMode.dark: '深色',
};

const Map<FlvpProxyMode, String> flvpModeLabels = {
  FlvpProxyMode.rule: '规则',
  FlvpProxyMode.global: '全局',
  FlvpProxyMode.direct: '直连',
};

const List<String> flvpLogLevels = ['info', 'debug', 'warn', 'error'];

const Map<String, String> flvpStacks = {
  'mixed': 'Mixed',
  'gvisor': 'gVisor',
  'system': 'System',
};
