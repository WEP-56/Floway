import 'dart:async';

import 'package:floway/features/form/form.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/ui/sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/rule_row.dart';

/// 附加规则：全局追加规则的增删改、排序与搜索，读写上游 `globalRulesProvider`。
/// 表单沿用上游 `RuleForm`，动作直接调用数据库层的 put / delAll / order。
class FlvpAddedRulesPage extends ConsumerStatefulWidget {
  const FlvpAddedRulesPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpAddedRulesPage> createState() => _FlvpAddedRulesPageState();
}

class _FlvpAddedRulesPageState extends ConsumerState<FlvpAddedRulesPage> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _keyword => _query.text.trim().toLowerCase();

  List<Rule> _visible(List<Rule> rules) {
    final keyword = _keyword;
    if (keyword.isEmpty) return rules;
    return [
      for (final rule in rules)
        if ((rule.rawValue).toLowerCase().contains(keyword))
          rule,
    ];
  }

  Future<void> _addOrEdit([Rule? rule]) async {
    final res = await showFormSheet<Rule>(
      context: context,
      builder: (_) => RuleForm(rule: rule),
    );
    if (res == null || !mounted) return;
    ref.read(globalRulesProvider.notifier).put(res);
  }

  Future<void> _delete(Rule rule) async {
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '删除规则',
      message: '确定删除「${rule.rawValue}」吗？',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok != true || !mounted) return;
    ref.read(globalRulesProvider.notifier).delAll([rule.id]);
  }

  void _reorder(int oldIndex, int newIndex) {
    ref.read(globalRulesProvider.notifier).order(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final rulesState = ref.watch(globalRulesProvider);
    final all = rulesState.value ?? const <Rule>[];
    final rules = _visible(all);
    final searching = _keyword.isNotEmpty;

    final search = _SearchBar(
      controller: _query,
      onChanged: (_) => setState(() {}),
    );

    Widget body;
    if (rulesState.isLoading && all.isEmpty) {
      body = const Center(child: FlvpSpinner(size: 22));
    } else if (all.isEmpty) {
      body = _empty(colors, '还没有附加规则', '点右上角加号新增一条');
    } else if (rules.isEmpty) {
      body = _empty(colors, '没有匹配的规则', '换个关键字试试');
    } else if (searching) {
      body = ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: rules.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, index) => FlvpRuleRow(
          rule: rules[index],
          onEdit: () => _addOrEdit(rules[index]),
          onDelete: () => _delete(rules[index]),
        ),
      );
    } else {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
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
            indexWidget: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FlvpIcon('MoreVertical', size: 18, color: colors.ink3),
              ),
            ),
            onEdit: () => _addOrEdit(rules[index]),
            onDelete: () => _delete(rules[index]),
          ),
        ),
      );
    }

    return FlvpPageScaffold(
      title: '附加规则',
      subtitle: '${all.length} 条 · 按顺序追加到配置',
      scrollable: false,
      actions: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: search,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(FlvpColors colors, String title, String hint) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          FlvpIcon('Route', size: 26, color: colors.ink3),
          Text(title, style: flvpText(13.5, color: colors.ink3)),
          Text(hint, style: flvpText(12, weight: FontWeight.w400, color: colors.ink3)),
        ],
      ),
    );
  }
}


class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surf2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          FlvpIcon('Search', size: 16, color: colors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              style: flvpText(13.5, color: colors.ink),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索规则内容',
                hintStyle: flvpText(13.5, color: colors.ink3),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                widget.controller.clear();
                widget.onChanged('');
              },
              child: FlvpIcon('X', size: 15, color: colors.ink3),
            ),
        ],
      ),
    );
  }
}
