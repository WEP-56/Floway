import 'dart:async';

import 'package:floway/views/config/filters.dart';
import 'package:floway/views/config/providers.dart';
import 'package:floway/views/profiles/custom/custom_proxies.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/upstream_page.dart';

/// 自定义资源：代理资源、规则 Provider 与过滤器。
///
/// 按本轮要求不再提供「图标集」入口（上游 IconSetsView 仍保留在代码里，
/// 只是设置页不再暴露）。
class FlvpCustomResourcesPage extends StatelessWidget {
  const FlvpCustomResourcesPage({super.key});

  void _open(BuildContext context, Widget page) {
    unawaited(openFlvpUpstreamPage(context, page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpPageScaffold(
      title: '自定义资源',
      subtitle: '供所有配置复用的代理与规则资源',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '资源',
            footer: '这些资源属于应用级配置，不随单份订阅变化；在配置里用同名引用。',
            children: [
              FlvpSettingsLink(
                icon: 'Server',
                title: '代理资源',
                subtitle: '自定义代理、Provider 与分组',
                onTap: () => _open(context, const CustomProxiesView()),
              ),
              FlvpSettingsLink(
                icon: 'Route',
                title: '规则 Provider',
                subtitle: '远程规则集与本地规则文件',
                onTap: () => _open(context, const ClashProvidersView()),
              ),
              FlvpSettingsLink(
                icon: 'SlidersHorizontal',
                title: '过滤器',
                subtitle: '对订阅内容做替换与剔除',
                onTap: () => _open(context, const FiltersView()),
              ),
            ],
          ),
          Text(
            '图标集已从自定义资源中移除：分组图标改用配置里的名称与内置图标。',
            style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
          ),
        ],
      ),
    );
  }
}
