import 'package:material_ui/material_ui.dart';

import '../design/theme_scope.dart';
import '../icons/flvp_icon.dart';
import 'controls.dart';
import 'surfaces.dart';

/// 设置类二级页共用的一组行/卡片：与一级设置页同一套间距、图标与字重。
class FlvpSettingsSection extends StatelessWidget {
  const FlvpSettingsSection({
    super.key,
    required this.title,
    this.footer,
    required this.children,
  });

  final String title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSectionLabel(title: title),
          FlvpCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                footer!,
                style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行设置项：图标 + 标题 + 说明 + 右侧内容。
class FlvpSettingsRow extends StatelessWidget {
  const FlvpSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => FlvpRow(
    icon: FlvpIcon(icon, size: 19),
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    trailing: trailing,
  );
}

class FlvpSettingsToggle extends StatelessWidget {
  const FlvpSettingsToggle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FlvpSettingsRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () => onChanged(!value),
    trailing: FlvpSwitch(value: value, onChanged: onChanged, label: title),
  );
}

/// 一行跳转项：右侧箭头。
class FlvpSettingsLink extends StatelessWidget {
  const FlvpSettingsLink({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FlvpSettingsRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    trailing: FlvpIcon(
      'ChevronRight',
      size: 16,
      color: FlvpThemeScope.colorsOf(context).ink3,
    ),
  );
}

/// 一行“名称 — 值”项，值本身可点开选择。
class FlvpSettingsValue extends StatelessWidget {
  const FlvpSettingsValue({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final String icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpSettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
            ),
          ),
          FlvpIcon('ChevronRight', size: 16, color: colors.ink3),
        ],
      ),
    );
  }
}
