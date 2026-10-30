import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../icons/flvp_icon.dart';
import '../store/design_store.dart';
import '../store/models.dart';
import '../store/store_scope.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/ripple.dart';
import '../widgets/surfaces.dart';

const _all = '全部';

/// pages/Nodes.tsx
class FlvpNodesPage extends StatefulWidget {
  const FlvpNodesPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  State<FlvpNodesPage> createState() => _FlvpNodesPageState();
}

class _FlvpNodesPageState extends State<FlvpNodesPage> {
  final TextEditingController _query = TextEditingController();
  String _group = _all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = FlvpStoreScope.of(context);
    final colors = FlvpThemeScope.colorsOf(context);
    final mobile = widget.platform == FlvpPlatform.mobile;
    final allGroups = <String>[];
    for (final node in store.nodes) {
      if (!allGroups.contains(node.sub)) allGroups.add(node.sub);
    }
    final keyword = _query.text.trim().toLowerCase();
    final groups = <String, List<NodeInfo>>{};
    for (final node in store.nodes) {
      if (_group != _all && node.sub != _group) continue;
      if (keyword.isNotEmpty &&
          !node.name.toLowerCase().contains(keyword) &&
          !node.proto.toLowerCase().contains(keyword)) {
        continue;
      }
      groups.putIfAbsent(node.sub, () => []).add(node);
    }

    final chips = [
      for (final group in [_all, ...allGroups])
        FlvpChip(
          label: group,
          selected: _group == group,
          onTap: () => setState(() => _group = group),
        ),
    ];
    final search = _SearchBar(
      controller: _query,
      onChanged: (_) => setState(() {}),
      width: mobile ? null : 300,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = !mobile && constraints.maxWidth >= 768;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            if (store.policyGroups.isNotEmpty) ...[
              Text(
                '规则模式按策略组分流；下方节点选择用于全局模式。',
                style: flvpText(12, color: colors.ink3),
              ),
              for (final group in store.policyGroups)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    Text(
                      '${group.name} · ${group.type}',
                      style: flvpText(13, color: colors.ink2),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (group.type == 'select')
                      DropdownButtonFormField<String>(
                        key: ValueKey('${group.id}:${group.selectedId}'),
                        initialValue: group.selectedId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final member in group.members.entries)
                            DropdownMenuItem(
                              value: member.key,
                              child: Text(
                                member.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            store.selectGroupMember(group.id, value);
                          }
                        },
                      )
                    else
                      Text(
                        '${group.members.length} 个成员 · 内核自动选择',
                        style: flvpText(12, color: colors.ink3),
                      ),
                  ],
                ),
            ],
            if (mobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  search,
                  // `-mx-4 overflow-x-auto px-4`: the chip strip bleeds into
                  // the page gutter and scrolls edge to edge.
                  SizedBox(
                    height: 32,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: constraints.maxWidth + 32,
                      maxWidth: constraints.maxWidth + 32,
                      child: Transform.translate(
                        offset: const Offset(-16, 0),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(spacing: 8, children: chips),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  search,
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              ),
            if (store.testing) const FlvpWavyProgress(),
            if (groups.isEmpty)
              FlvpCard(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    FlvpIcon('Search', size: 26, color: colors.ink3),
                    Text(
                      '没有找到匹配的节点',
                      style: flvpText(
                        13.5,
                        weight: FontWeight.w400,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            for (final entry in groups.entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlvpSectionLabel(
                    title: entry.key,
                    trailing: Text(
                      '${entry.value.length} 个节点',
                      style: flvpText(12, color: colors.ink3),
                    ),
                  ),
                  FlvpCard(
                    padding: const EdgeInsets.all(6),
                    child: _nodeGrid(store, entry.value, twoColumns),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _nodeGrid(
    FlvpDesignStore store,
    List<NodeInfo> nodes,
    bool twoColumns,
  ) {
    Widget row(NodeInfo node) => _NodeRow(
      node: node,
      selected: node.id == store.selectedNodeId,
      testing: store.testing,
      onSelect: () => store.selectNode(node.id),
    );
    // `@3xl:grid-cols-2 @3xl:[&>:only-child]:col-span-2`, gap-0.5.
    if (!twoColumns || nodes.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [for (final node in nodes) row(node)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        for (var i = 0; i < nodes.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Expanded(child: row(nodes[i])),
              Expanded(
                child: i + 1 < nodes.length
                    ? row(nodes[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    this.width,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double? width;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_focus, widget.controller]),
      builder: (context, _) => AnimatedContainer(
        duration: FlvpMotion.control,
        width: widget.width,
        height: 48,
        padding: const EdgeInsets.only(left: 16, right: 6),
        decoration: BoxDecoration(
          color: colors.surf2,
          borderRadius: BorderRadius.circular(999),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _focus.hasFocus ? colors.primary : const Color(0x00000000),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            FlvpIcon('Search', size: 18, color: colors.ink2),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                maxLines: 1,
                cursorColor: colors.primary,
                style: flvpText(14, weight: FontWeight.w400, color: colors.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '搜索节点或协议',
                  hintStyle: flvpText(
                    14,
                    weight: FontWeight.w400,
                    color: colors.ink3,
                  ),
                ),
              ),
            ),
            if (widget.controller.text.isNotEmpty)
              FlvpHover(
                builder: (context, hovered) => GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                  child: Semantics(
                    button: true,
                    label: '清除',
                    child: AnimatedContainer(
                      duration: FlvpMotion.hover,
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hovered
                            ? colors.inkLayer()
                            : const Color(0x00000000),
                      ),
                      child: FlvpIcon('X', size: 16, color: colors.ink2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.selected,
    required this.testing,
    required this.onSelect,
  });

  final NodeInfo node;
  final bool selected;
  final bool testing;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final special = switch (node.id) {
      'auto' => 'Zap',
      'home' => 'House',
      'office' => 'Building2',
      _ => null,
    };
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: selected ? colors.onpcontainer : colors.ink,
        borderRadius: BorderRadius.circular(18),
        child: GestureDetector(
          onTap: onSelect,
          child: AnimatedContainer(
            duration: FlvpMotion.shape,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colors.pcontainer
                  : (hovered ? colors.inkHover() : const Color(0x00000000)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              spacing: 14,
              children: [
                AnimatedContainer(
                  duration: FlvpMotion.shape,
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : colors.surf2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: special != null
                      ? FlvpIcon(
                          special,
                          size: 17,
                          color: selected ? colors.onprimary : colors.ink2,
                        )
                      : Text(
                          node.region,
                          style: flvpText(
                            12,
                            weight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: selected ? colors.onprimary : colors.ink2,
                          ),
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          14.5,
                          color: selected ? colors.onpcontainer : colors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        node.proto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          12.5,
                          weight: FontWeight.w400,
                          color: selected
                              ? colors.onpcontainer.withValues(alpha: 0.75)
                              : colors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                FlvpLatencyBadge(ms: node.latency, testing: testing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
