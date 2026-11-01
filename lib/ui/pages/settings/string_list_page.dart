import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 通用字符串列表页：排除域名、路由地址这类「一行一条」的配置。
class FlvpStringListPage extends StatelessWidget {
  const FlvpStringListPage({
    super.key,
    required this.platform,
    required this.title,
    this.subtitle,
    required this.values,
    required this.onChanged,
    this.placeholder,
    this.validator,
    this.footer,
    this.emptyLabel = '还没有条目',
  });

  final FlvpPlatform platform;
  final String title;
  final String? subtitle;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? placeholder;
  final String? Function(String value, List<String> values)? validator;
  final String? footer;
  final String emptyLabel;

  Future<void> _addOrEdit(BuildContext context, {String? current}) async {
    final next = await showFlvpTextPrompt(
      context: context,
      platform: platform,
      title: current == null ? '添加' : '编辑',
      subtitle: subtitle,
      value: current ?? '',
      placeholder: placeholder,
      validator: (value) {
        if (value.isEmpty) return '不能为空';
        if (value != current && values.contains(value)) return '这一项已经存在';
        return validator?.call(value, values);
      },
    );
    if (next == null || next == current) return;
    final result = List<String>.from(values);
    if (current == null) {
      result.add(next);
    } else {
      result[result.indexOf(current)] = next;
    }
    onChanged(result);
  }

  void _remove(String value) {
    onChanged([...values.where((item) => item != value)]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpPageScaffold(
      title: title,
      subtitle: subtitle,
      actions: [
        FlvpIconButton(
          label: '添加',
          dimension: 40,
          onPressed: () => _addOrEdit(context),
          icon: const FlvpIcon('Plus', size: 19),
        ),
      ],
      child: FlvpSettingsSection(
        title: '$title（${values.length}）',
        footer: footer,
        children: [
          if (values.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Column(
                spacing: 10,
                children: [
                  FlvpIcon('Route', size: 24, color: colors.ink3),
                  Text(emptyLabel, style: flvpText(13, color: colors.ink3)),
                ],
              ),
            )
          else
            for (final value in values)
              FlvpSettingsRow(
                icon: 'Route',
                title: value,
                onTap: () => _addOrEdit(context, current: value),
                trailing: FlvpIconButton(
                  label: '删除 $value',
                  dimension: 32,
                  onPressed: () => _remove(value),
                  icon: FlvpIcon('X', size: 14, color: colors.ink3),
                ),
              ),
        ],
      ),
    );
  }
}
