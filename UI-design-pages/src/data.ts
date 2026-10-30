export interface NodeInfo {
  id: string;
  name: string;
  sub: string;
  proto: string;
  region: string;
  latency: number | null;
}

export interface SubInfo {
  id: string;
  name: string;
  url: string;
  used: number;
  total: number;
  expire: string;
  updated: string;
  active: boolean;
}

export const APP_VERSION = "1.4.2";
export const CORE_VERSION = "sing-box 1.11.0";
export const BUILD_DATE = "2026-10-12";

export const INITIAL_NODES: NodeInfo[] = [
  { id: "auto", name: "自动选择", sub: "策略组", proto: "延迟最低优先", region: "", latency: 42 },
  { id: "hk-01", name: "香港 01", sub: "FLVP 高级订阅", proto: "Hysteria2", region: "HK", latency: 42 },
  { id: "hk-02", name: "香港 02", sub: "FLVP 高级订阅", proto: "Hysteria2", region: "HK", latency: 58 },
  { id: "jp-01", name: "东京 01", sub: "FLVP 高级订阅", proto: "VLESS", region: "JP", latency: 86 },
  { id: "tw-01", name: "台北 01", sub: "FLVP 高级订阅", proto: "Shadowsocks", region: "TW", latency: 97 },
  { id: "sg-01", name: "新加坡 01", sub: "FLVP 高级订阅", proto: "Trojan", region: "SG", latency: 121 },
  { id: "us-01", name: "洛杉矶 01", sub: "FLVP 高级订阅", proto: "VLESS", region: "US", latency: 168 },
  { id: "home", name: "家庭网关", sub: "自建节点", proto: "VMess", region: "", latency: 8 },
  { id: "office", name: "办公室", sub: "自建节点", proto: "VMess", region: "", latency: 24 },
];

export const INITIAL_SUBS: SubInfo[] = [
  {
    id: "s1",
    name: "FLVP 高级订阅",
    url: "https://api.flvp.io/v1/subscribe?token=8f2a91c7d4",
    used: 42.6,
    total: 200,
    expire: "2027-08-14",
    updated: "3 分钟前",
    active: true,
  },
  {
    id: "s2",
    name: "备用订阅",
    url: "https://cdn.flvp.net/clash/config?key=b71d30",
    used: 8.2,
    total: 50,
    expire: "2027-03-01",
    updated: "昨天 21:07",
    active: false,
  },
  {
    id: "s3",
    name: "免费节点池",
    url: "https://free.flvp.io/airport/list",
    used: 118.4,
    total: 150,
    expire: "2026-11-20",
    updated: "6 天前",
    active: false,
  },
];

export const SHORTCUTS: { keys: string[]; desc: string }[] = [
  { keys: ["Ctrl", "Shift", "F"], desc: "显示 / 隐藏主窗口" },
  { keys: ["Ctrl", "Shift", "P"], desc: "开启 / 停止代理" },
  { keys: ["Ctrl", "Shift", "N"], desc: "切换到下一个节点" },
  { keys: ["Ctrl", "Shift", "S"], desc: "切换系统代理" },
  { keys: ["Ctrl", "Shift", "C"], desc: "复制终端代理命令" },
];

export type ThemeMode = "system" | "light" | "dark";
export type Lang = "zh" | "en" | "ja";
export type ProxyMode = "rule" | "global" | "direct";

/** Material You seed colors — h: oklch hue, k: chroma factor (keeps colors in gamut) */
export const ACCENTS = {
  indigo: { label: "靛蓝", h: 275, k: 1 },
  teal: { label: "青碧", h: 200, k: 0.72 },
  green: { label: "松绿", h: 150, k: 0.72 },
  rose: { label: "玫瑰", h: 12, k: 0.9 },
  amber: { label: "琥珀", h: 80, k: 0.65 },
} as const;

export type AccentKey = keyof typeof ACCENTS;
export const ACCENT_KEYS = Object.keys(ACCENTS) as AccentKey[];

/** Android-style palette swatch: primary on top, secondary / tertiary below */
export function swatchBackground(key: AccentKey): string {
  const { h, k } = ACCENTS[key];
  const a = `oklch(0.56 ${(0.17 * k).toFixed(3)} ${h})`;
  const b = `oklch(0.86 ${(0.06 * k).toFixed(3)} ${h})`;
  const c = `oklch(0.72 ${(0.1 * k).toFixed(3)} ${h + 60})`;
  return `conic-gradient(from 270deg, ${a} 0 50%, ${c} 50% 75%, ${b} 75% 100%)`;
}

export interface AppSettings {
  language: Lang;
  theme: ThemeMode;
  accent: AccentKey;
  mode: ProxyMode;
  autoStart: boolean;
  silentStart: boolean;
  autoConnect: boolean;
  closeBehavior: "tray" | "quit";
  statsScope: "total" | "session";
  mixedPort: string;
  socksPort: string;
  allowLan: boolean;
  systemProxy: boolean;
  tunMode: boolean;
  dns: string;
  sniff: boolean;
  ipv6: boolean;
  logLevel: string;
  stack: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  language: "zh",
  theme: "light",
  accent: "indigo",
  mode: "rule",
  autoStart: true,
  silentStart: true,
  autoConnect: true,
  closeBehavior: "tray",
  statsScope: "total",
  mixedPort: "7890",
  socksPort: "7891",
  allowLan: false,
  systemProxy: true,
  tunMode: false,
  dns: "https://dns.alidns.com/dns-query",
  sniff: true,
  ipv6: false,
  logLevel: "info",
  stack: "mixed",
};

export const LANGUAGE_LABEL: Record<Lang, string> = {
  zh: "简体中文",
  en: "English",
  ja: "日本語",
};

export const THEME_LABEL: Record<ThemeMode, string> = {
  system: "跟随系统",
  light: "浅色",
  dark: "深色",
};

export const MODE_LABEL: Record<ProxyMode, string> = {
  rule: "规则",
  global: "全局",
  direct: "直连",
};

export const LOG_LEVELS = ["info", "debug", "warn", "error"];

export const STACKS: Record<string, string> = {
  mixed: "Mixed",
  gvisor: "gVisor",
  system: "System",
};
