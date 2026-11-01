import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/views/hotkey.dart' show HotKeyRecorder;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';

/// 快捷键：全局快捷键的查看、录制与清除。
///
/// 录制界面沿用上游 `HotKeyRecorder`（按键捕获与冲突提示都在里面），
/// 列表本身换成 Floway 的行与键帽。
class FlvpHotKeyPage extends ConsumerWidget {
  const FlvpHotKeyPage({super.key});

  static const _sections = [
    ('通用', [HotAction.view, HotAction.start, HotAction.exit]),
    ('出站模式', [
      HotAction.mode,
      HotAction.ruleMode,
      HotAction.globalMode,
      HotAction.directMode,
    ]),
    ('网络', [HotAction.proxy, HotAction.tun, HotAction.copyEnv]),
    ('代理', [HotAction.delayTest, HotAction.updateProfiles]),
  ];

  static String _icon(HotAction action) => switch (action) {
    HotAction.view => 'Eye',
    HotAction.start => 'Power',
    HotAction.exit => 'LogOut',
    HotAction.mode => 'SlidersHorizontal',
    HotAction.ruleMode => 'Route',
    HotAction.globalMode => 'Globe',
    HotAction.directMode => 'Globe2',
    HotAction.proxy => 'Zap',
    HotAction.tun => 'Network',
    HotAction.copyEnv => 'Copy',
    HotAction.delayTest => 'Gauge',
    HotAction.updateProfiles => 'RefreshCw',
  };

  static bool _sameCombination(HotKeyAction a, HotKeyAction b) =>
      a.key != null &&
      a.key == b.key &&
      keyboardModifierListEquality.equals(a.modifiers, b.modifiers);

  static List<HotKeyAction> _withBinding(
    List<HotKeyAction> actions,
    HotKeyAction binding,
  ) {
    final isBound = binding.key != null;
    var isPlaced = false;
    final result = <HotKeyAction>[];
    for (final item in actions) {
      if (item.action == binding.action) {
        isPlaced = true;
        if (isBound) result.add(binding);
      } else if (!(isBound && _sameCombination(item, binding))) {
        result.add(item);
      }
    }
    if (isBound && !isPlaced) result.add(binding);
    return result;
  }

  void _save(WidgetRef ref, HotKeyAction binding) {
    final notifier = ref.read(hotKeyActionsProvider.notifier);
    notifier.value = _withBinding(notifier.value, binding);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final labels = ShortcutLabels.host();
    return FlvpPageScaffold(
      title: '快捷键',
      subtitle: '在系统任意位置生效的全局快捷键',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (title, actions) in _sections)
            FlvpSettingsSection(
              title: title,
              children: [
                for (final action in actions)
                  _HotKeyRow(
                    action: action,
                    labels: labels,
                    icon: _icon(action),
                    onSave: (binding) => _save(ref, binding),
                    colors: colors,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HotKeyRow extends ConsumerWidget {
  const _HotKeyRow({
    required this.action,
    required this.labels,
    required this.icon,
    required this.onSave,
    required this.colors,
  });

  final HotAction action;
  final ShortcutLabels labels;
  final String icon;
  final void Function(HotKeyAction binding) onSave;
  final FlvpColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = ref.watch(getHotKeyActionProvider(action));
    final failure = ref.watch(hotKeyFailuresProvider.select((s) => s[action]));
    final key = binding.key;
    return FlvpSettingsRow(
      icon: icon,
      title: action.label,
      subtitle: failure,
      onTap: () => dialogs.showCommonDialog(
        child: HotKeyRecorder(hotKeyAction: binding, labels: labels),
      ),
      trailing: key == null
          ? Text(
              '未设置',
              style: flvpText(13, weight: FontWeight.w400, color: colors.ink3),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                for (final part in labels.parts(binding.modifiers, key))
                  FlvpKbd(label: part),
                FlvpIconButton(
                  label: '清除快捷键',
                  dimension: 32,
                  onPressed: () =>
                      onSave(HotKeyAction(action: action)),
                  icon: FlvpIcon(
                    'X',
                    size: 14,
                    color: failure == null ? colors.ink3 : colors.err,
                  ),
                ),
              ],
            ),
    );
  }
}
