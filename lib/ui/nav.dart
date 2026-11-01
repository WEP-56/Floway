/// Navigation entries mirrored from the design's src/nav.ts.
///
/// The Windows rail and the Android navigation bar share the same five
/// entries: 仪表盘 / 代理 / 配置 / 信息 / 设置 (TODO.md section 2).
enum FlvpPageKey { dashboard, proxies, profiles, info, settings }

class FlvpNavItem {
  const FlvpNavItem(this.key, this.label, this.icon);

  final FlvpPageKey key;
  final String label;

  /// lucide icon name (see lib/ui/icons/flvp_icons.dart).
  final String icon;
}

const List<FlvpNavItem> flvpNavItems = [
  FlvpNavItem(FlvpPageKey.dashboard, '仪表盘', 'Gauge'),
  FlvpNavItem(FlvpPageKey.proxies, '代理', 'Server'),
  FlvpNavItem(FlvpPageKey.profiles, '配置', 'Rss'),
  FlvpNavItem(FlvpPageKey.info, '信息', 'Activity'),
  FlvpNavItem(FlvpPageKey.settings, '设置', 'Settings'),
];

/// The Android bar keeps four entries: five at a phone width are too tight, so
/// 信息 moves into the settings page (see `FlvpSettingsPage.onNavigate`).
const List<FlvpNavItem> flvpMobileNavItems = [
  FlvpNavItem(FlvpPageKey.dashboard, '仪表盘', 'Gauge'),
  FlvpNavItem(FlvpPageKey.proxies, '代理', 'Server'),
  FlvpNavItem(FlvpPageKey.profiles, '配置', 'Rss'),
  FlvpNavItem(FlvpPageKey.settings, '设置', 'Settings'),
];

const Map<FlvpPageKey, String> flvpPageTitles = {
  FlvpPageKey.dashboard: '仪表盘',
  FlvpPageKey.proxies: '代理',
  FlvpPageKey.profiles: '配置',
  FlvpPageKey.info: '信息',
  FlvpPageKey.settings: '设置',
};