import 'dart:async';

import 'package:floway/features/form/form.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/ui/sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/rule_row.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';
import '../settings/rules_page.dart';

/// 配置覆写的「标准」内容：这份配置自己追加的规则。
///
/// 与上游 `StandardContent` 同一套动作（`profileRulesProvider` 的 put /
/// putAll / delAll / order、`profilesProvider` 的 matchTarget），呈现换成
/// Floway 的规则卡片、选择模式与行式页脚。
class FlvpProfileRulesPage extends ConsumerStatefulWidget {
  const FlvpProfileRulesPage({
    super.key,
    required this.profileId,
    required this.platform,
    this.showMatchTarget = true,
  });

  final int profileId;
  final FlvpPlatform platform;

  /// 覆写页需要「匹配目标」；自定义工作区里不需要。
  final bool showMatchTarget;

  @override
  ConsumerState<FlvpProfileRulesPage> createState() =>
      _FlvpProfileRulesPageState();
}

class _FlvpProfileRulesPageState extends ConsumerState<FlvpProfileRulesPage> {
  final Set<int> _selected = {};

  int get _profileId => widget.profileId;

  ProfileRules get _rules => ref.read(profileRulesProvider(_profileId).notifier);

  List<Rule> get _values => ref.read(profileRulesProvider(_profileId)).value ?? const [];

  Future<void> _addOrEdit([Rule? rule]) async {
    final res = await showFormSheet<Rule>(
      context: context,
      builder: (_) => RuleForm(rule: rule),
    );
    if (res == null || !mounted) return;
    _rules.put(res);
  }

  Future<void> _presets() async {
    await showSheet<void>(
      context: context,
      builder: (_) => RulePresetSheet(onAdd: _rules.putAll),
    );
  }

  void _toggle(int ruleId) {
    setState(() {
      if (!_selected.remove(ruleId)) _selected.add(ruleId);
    });
  }

  void _selectAll() {
    final ids = {for (final rule in _values) rule.id};
    setState(() {
      if (_selected.containsAll(ids)) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '删除规则',
      message: '确定删除选中的 ${_selected.length} 条规则吗？',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    _rules.delAll(_selected.toList());
    setState(_selected.clear);
  }

  void _reorder(int oldIndex, int newIndex) =>
      _rules.order(oldIndex, newIndex);

  Future<void> _pickMatchTarget() async {
    final config = ref.read(clashConfigProvider(_profileId)).value;
    final groups = config?.proxyGroups ?? const <ProxyGroup>[];
    final proxies = config?.proxies ?? const <Proxy>[];
    final groupNames = {for (final group in groups) group.name};
    final current = ref.read(profileProvider(_profileId))?.matchTarget ?? '';
    final host = FlvpModalHost.of(context);

    void pick(String value) {
      ref.read(profilesProvider.notifier).updateProfile(_profileId, (state) {
        return state.copyWith(matchTarget: value.isEmpty ? null : value);
      });
      host.close();
    }

    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: '匹配目标',
        subtitle: '没有命中任何规则的流量交给这里',
        onClose: host.close,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440, maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            children: [
              _TargetSection(
                label: '默认',
                items: const [('', '跟随配置')],
                current: current,
                onPick: pick,
              ),
              if (RuleTarget.ruleTargetNames
                  .where((name) => !groupNames.contains(name))
                  .isNotEmpty)
                _TargetSection(
                  label: '基础策略',
                  items: [
                    for (final name in RuleTarget.ruleTargetNames)
                      if (!groupNames.contains(name)) (name, '内置策略'),
                  ],
                  current: current,
                  onPick: pick,
                ),
              if (groups.isNotEmpty)
                _TargetSection(
                  label: '策略组',
                  items: [for (final group in groups) (group.name, group.type.name)],
                  current: current,
                  onPick: pick,
                ),
              if (proxies.isNotEmpty)
                _TargetSection(
                  label: '代理',
                  items: [for (final proxy in proxies) (proxy.name, proxy.type)],
                  current: current,
                  onPick: pick,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final rulesState = ref.watch(profileRulesProvider(_profileId));
    final rules = rulesState.value ?? const <Rule>[];
    final selected = _selected.intersection({for (final r in rules) r.id});
    final matchTarget = ref.watch(
      profileProvider(_profileId).select((state) => state?.matchTarget),
    );
    final clashConfig = ref.watch(clashConfigProvider(_profileId)).value;
    final invalidTarget =
        matchTarget != null &&
        clashConfig != null &&
        !RuleTarget.ruleTargets.contains(matchTarget) &&
        !clashConfig.proxyGroups.any((item) => item.name == matchTarget) &&
        !clashConfig.proxies.any((item) => item.name == matchTarget);

    Widget list;
    if (rulesState.isLoading && rules.isEmpty) {
      list = const Center(child: FlvpSpinner(size: 22));
    } else if (rules.isEmpty) {
      list = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            FlvpIcon('Route', size: 26, color: colors.ink3),
            Text('还没有附加规则', style: flvpText(13.5, color: colors.ink3)),
            Text(
              '这些规则会按顺序追加到配置末尾',
              style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
            ),
            const SizedBox(height: 6),
            FlvpButton(
              variant: FlvpButtonVariant.tonal,
              size: FlvpControlSize.sm,
              label: '添加规则',
              icon: const FlvpIcon('Plus', size: 16),
              onPressed: () => _addOrEdit(),
            ),
          ],
        ),
      );
    } else {
      list = ReorderableListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        buildDefaultDragHandles: false,
        itemCount: rules.length,
        onReorderItem: _reorder,
        proxyDecorator: (child, index, animation) => Material(
          color: const Color(0x00000000),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
            child: child,
          ),
        ),
        itemBuilder: (_, index) => Padding(
          key: ValueKey(rules[index].id),
          padding: const EdgeInsets.only(bottom: 8),
          child: FlvpRuleRow(
            rule: rules[index],
            selected: selected.contains(rules[index].id),
            onSelect: () => _toggle(rules[index].id),
            indexWidget: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FlvpIcon('MoreVertical', size: 18, color: colors.ink3),
              ),
            ),
            onEdit: () => _addOrEdit(rules[index]),
            onDelete: () => _deleteOne(rules[index]),
          ),
        ),
      );
    }

    final selecting = selected.isNotEmpty;
    return FlvpPageScaffold(
      title: '附加规则',
      subtitle: '${rules.length} 条 · 追加到配置末尾',
      scrollable: false,
      actions: selecting
          ? [
              FlvpIconButton(
                label: '删除选中',
                dimension: 40,
                onPressed: _deleteSelected,
                icon: FlvpIcon('Trash2', size: 19, color: colors.err),
              ),
              FlvpIconButton(
                label: '全选',
                dimension: 40,
                onPressed: _selectAll,
                icon: const FlvpIcon('Check', size: 19),
              ),
            ]
          : [
              FlvpIconButton(
                label: '规则预设',
                dimension: 40,
                onPressed: _presets,
                icon: const FlvpIcon('SlidersHorizontal', size: 19),
              ),
              FlvpIconButton(
                label: '添加规则',
                dimension: 40,
                onPressed: () => _addOrEdit(),
                icon: const FlvpIcon('Plus', size: 20),
              ),
            ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: list,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: FlvpSettingsSection(
              title: '覆写选项',
              children: [
                if (widget.showMatchTarget)
                  FlvpSettingsValue(
                    icon: 'Zap',
                    title: '匹配目标',
                    subtitle: '没有命中规则时使用的出站',
                    value: matchTarget ?? '跟随配置',
                    onTap: _pickMatchTarget,
                  ),
                FlvpSettingsLink(
                  icon: 'Route',
                  title: '全局附加规则',
                  subtitle: '对所有配置生效，排在配置自己的规则之后',
                  onTap: () => pushFlvpPage<void>(
                    context,
                    FlvpAddedRulesPage(platform: widget.platform),
                  ),
                ),
              ],
            ),
          ),
          if (invalidTarget)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 36, 12),
              child: Text(
                '匹配目标「$matchTarget」在当前配置里不存在，应用时会回落到直连。',
                style: flvpText(12, weight: FontWeight.w400, color: colors.warn),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteOne(Rule rule) async {
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '删除规则',
      message: '确定删除「${rule.rawValue}」吗？',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    _rules.delAll([rule.id]);
    if (_selected.remove(rule.id)) setState(() {});
  }
}

class _TargetSection extends StatelessWidget {
  const _TargetSection({
    required this.label,
    required this.items,
    required this.current,
    required this.onPick,
  });

  final String label;
  final List<(String, String)> items;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlvpSectionLabel(title: label),
        for (final (value, subtitle) in items)
          FlvpRow(
            title: value.isEmpty ? '跟随配置' : value,
            subtitle: subtitle,
            onTap: () => onPick(value),
            trailing: current == value
                ? FlvpIcon('Check', size: 16, color: colors.primary)
                : null,
          ),
      ],
    );
  }
}
