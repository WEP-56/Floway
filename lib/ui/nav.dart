/// Navigation entries mirrored from the design's src/nav.ts.
enum FlvpPageKey { dashboard, nodes, subs, settings }

class FlvpNavItem {
  const FlvpNavItem(this.key, this.label, this.icon);

  final FlvpPageKey key;
  final String label;

  /// lucide icon name (see lib/ui/icons/flvp_icons.dart).
  final String icon;
}

const List<FlvpNavItem> flvpNavItems = [
  FlvpNavItem(FlvpPageKey.dashboard, '仪表盘', 'Gauge'),
  FlvpNavItem(FlvpPageKey.nodes, '节点', 'Server'),
  FlvpNavItem(FlvpPageKey.subs, '订阅', 'Rss'),
  FlvpNavItem(FlvpPageKey.settings, '设置', 'Settings'),
];

const Map<FlvpPageKey, String> flvpPageTitles = {
  FlvpPageKey.dashboard: '仪表盘',
  FlvpPageKey.nodes: '节点',
  FlvpPageKey.subs: '订阅',
  FlvpPageKey.settings: '设置',
};
