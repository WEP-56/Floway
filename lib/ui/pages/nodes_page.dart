import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../icons/flvp_icon.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/ripple.dart';
import '../widgets/surfaces.dart';

/// pages/Nodes.tsx — 策略组与组内节点，数据全部来自上游 `groupsProvider`。
///
/// 搜索框在左、策略组小选择块在右（横向可滚，点边缘的块自动滚入视野）；
/// 下方只列当前策略组的成员：点行切换该组的选中节点，点延迟数字单独测速。
class FlvpNodesPage extends ConsumerStatefulWidget {
  const FlvpNodesPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpNodesPage> createState() => _FlvpNodesPageState();
}

class _FlvpNodesPageState extends ConsumerState<FlvpNodesPage> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _chipScroll = ScrollController();
  final Map<String, GlobalKey> _chipKeys = {};

  String? _groupName;

  @override
  void dispose() {
    _query.dispose();
    _chipScroll.dispose();
    super.dispose();
  }

  void _selectGroup(String name) {
    setState(() => _groupName = name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[name]?.currentContext;
      if (chipContext == null) return;
      // 点边缘的策略组时把它滚到视野中间，和设计稿的横向滑动一致。
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: FlvpMotion.control,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final mobile = widget.platform == FlvpPlatform.mobile;
    final groups = ref.watch(groupsProvider);
    final selectedMap = ref.watch(selectedMapProvider);
    final testing = ref.watch(delayTestingGroupsProvider).isNotEmpty;

    final current = groups.where((g) => g.name == _groupName).firstOrNull ??
        groups.firstOrNull;


    final keyword = _query.text.trim().toLowerCase();
    final members = current == null
        ? const <Proxy>[]
        : [
            for (final proxy in current.all)
              if (keyword.isEmpty ||
                  proxy.name.toLowerCase().contains(keyword) ||
                  proxy.type.toLowerCase().contains(keyword))
                proxy,
          ];
    final selectedName = current == null
        ? ''
        : current.getCurrentSelectedName(selectedMap[current.name] ?? '');

    final search = _SearchBar(
      controller: _query,
      onChanged: (_) => setState(() {}),
      width: mobile ? null : 300,
    );

    final chips = [
      for (final group in groups)
        FlvpChip(
          key: _chipKeys.putIfAbsent(group.name, () => GlobalKey()),
          label: group.name,
          selected: group.name == current?.name,
          onTap: () => _selectGroup(group.name),
        ),
    ];

    final chipStrip = SizedBox(
      height: 32,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _chipScroll,
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 8, children: chips),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = !mobile && constraints.maxWidth >= 768;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            if (mobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [search, chipStrip],
              )
            else
              Row(
                children: [
                  search,
                  const SizedBox(width: 12),
                  Expanded(child: chipStrip),
                ],
              ),
            if (testing) const FlvpWavyProgress(),
            if (groups.isEmpty)
              FlvpCard(
                padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    FlvpIcon('Network', size: 26, color: colors.ink3),
                    Text(
                      '启动代理后这里显示策略组',
                      style: flvpText(13.5, color: colors.ink3),
                    ),
                  ],
                ),
              )
            else if (members.isEmpty)
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
              )
            else ...[
              FlvpSectionLabel(
                title: current!.name,
                trailing: Text(
                  '${members.length} 个节点 · ${_groupTypeLabel(current)}',
                  style: flvpText(12, color: colors.ink3),
                ),
              ),
              FlvpCard(
                padding: const EdgeInsets.all(6),
                child: _nodeGrid(
                  members,
                  twoColumns,
                  current: current,
                  selectedName: selectedName,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _nodeGrid(
    List<Proxy> nodes,
    bool twoColumns, {
    required Group current,
    required String selectedName,
  }) {
    Widget row(Proxy node) => _NodeRow(
      proxy: node,
      groupName: current.name,
      selected: node.name == selectedName,
    );
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

  String _groupTypeLabel(Group group) => switch (group.type.name) {
    'select' => '手动选择',
    'urlTest' => '延迟最低优先',
    'fallback' => '故障转移',
    'loadBalance' => '负载均衡',
    'relay' => '链式代理',
    _ => group.type.name,
  };
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
  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final field = Container(
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
                hintText: '搜索节点或协议',
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
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

class _NodeRow extends ConsumerWidget {
  const _NodeRow({
    required this.proxy,
    required this.groupName,
    required this.selected,
  });

  final Proxy proxy;
  final String groupName;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final delay = ref.watch(delayProvider(proxyName: proxy.name));
    final testing = ref.watch(delayTestPhaseProvider(proxyName: proxy.name)) != null;

    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: selected ? colors.onpcontainer : colors.ink,
        borderRadius: BorderRadius.circular(18),
        child: GestureDetector(
          onTap: () => ref
              .read(proxiesActionProvider.notifier)
              .changeProxyDebounce(groupName, proxy.name),
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
                  child: _glyph(proxy, selected ? colors.onprimary : colors.ink2),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        proxy.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          14.5,
                          color: selected ? colors.onpcontainer : colors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        proxy.type.toUpperCase(),
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
                _DelayButton(
                  delay: delay,
                  testing: testing,
                  onTap: () => ref
                      .read(proxiesActionProvider.notifier)
                      .proxyDelayTest(proxy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glyph(Proxy proxy, Color color) {
    final name = proxy.name.toUpperCase();
    final icon = switch (name) {
      'DIRECT' || 'REJECT' || 'PASS' => 'Route',
      _ when name.contains('自动') || proxy.type == 'URLTest' => 'Zap',
      _ => null,
    };
    if (icon != null) return FlvpIcon(icon, size: 17, color: color);
    final label = proxy.name.runes.length >= 2
        ? String.fromCharCodes(proxy.name.runes.take(2))
        : proxy.name;
    return Text(
      label,
      style: flvpText(
        12,
        weight: FontWeight.w700,
        letterSpacing: 0.3,
        color: color,
      ),
    );
  }
}

/// 单点测速按钮：测速时给转圈和底色，平时显示延迟数字。
class _DelayButton extends StatelessWidget {
  const _DelayButton({
    required this.delay,
    required this.testing,
    required this.onTap,
  });

  final int? delay;
  final bool testing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Tooltip(
      message: testing ? '正在测速' : '点击测速',
      waitDuration: const Duration(milliseconds: 400),
      child: FlvpHover(
        builder: (context, hovered) => FlvpRipple(
          color: colors.ink,
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: testing ? null : onTap,
            child: AnimatedContainer(
              duration: FlvpMotion.control,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: testing
                    ? colors.pcontainer
                    : (hovered ? colors.inkHover() : const Color(0x00000000)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedSwitcher(
                duration: FlvpMotion.control,
                child: testing
                    ? Row(
                        key: const ValueKey('testing'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '测速中',
                            style: flvpText(12, color: colors.primary),
                          ),
                        ],
                      )
                    : FlvpLatencyBadge(
                        key: const ValueKey('idle'),
                        ms: delay,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
