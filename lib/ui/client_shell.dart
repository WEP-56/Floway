import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/bridge.dart';
import '../core/controller.dart';
import '../core/profile.dart';

const _titles = ['概览', '代理节点', '分流规则', '配置与设置'];
const _icons = [
  Icons.dashboard_outlined,
  Icons.hub_outlined,
  Icons.alt_route_rounded,
  Icons.tune_rounded,
];
const _subtitles = [
  '连接、流量与内核运行状态',
  '管理本地节点与代理组选择',
  '按顺序匹配，以最终规则兜底',
  '管理配置文件和本机参数',
];

String stateLabel(CoreState state) => switch (state) {
  CoreState.stopped => '已停止',
  CoreState.preparing => '正在准备',
  CoreState.starting => '正在启动',
  CoreState.running => '本地代理运行中',
  CoreState.applying => '正在应用配置',
  CoreState.stopping => '正在停止',
  CoreState.failed => '启动失败或连接中断',
};
String modeLabel(RoutingMode mode) => switch (mode) {
  RoutingMode.rule => '规则',
  RoutingMode.global => '全局',
  RoutingMode.direct => '直连',
};
String targetLabel(String target, Profile profile) => switch (target) {
  directTarget => '直连 DIRECT',
  rejectTarget => '拒绝 REJECT',
  proxyTarget => '代理组 PROXY',
  _ =>
    profile.nodes.where((n) => n.id == target).firstOrNull?.displayName ??
        '未知目标',
};
String bytesLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class ClientShell extends StatefulWidget {
  const ClientShell({super.key, required this.controller});
  final ClientController controller;
  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _page = 0;
  ClientController get c => widget.controller;
  bool get editable => c.initialized && !c.busy;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 840;
        return Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) ...[
                  NavigationRail(
                    selectedIndex: _page,
                    onDestinationSelected: (index) =>
                        setState(() => _page = index),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLow,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Icon(Icons.blur_on_rounded, size: 36),
                    ),
                    destinations: [
                      for (var i = 0; i < _titles.length; i++)
                        NavigationRailDestination(
                          icon: Icon(_icons[i]),
                          label: Text(_titles[i]),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 32 : 20,
                          24,
                          20,
                          20,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FLVPcore / ${_titles[_page]}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_subtitles[_page]),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Tooltip(
                              message: '早期开发版 · M0.1',
                              child: Chip(label: Text('DEV')),
                            ),
                          ],
                        ),
                      ),
                      if (!c.initialized)
                        const LinearProgressIndicator(minHeight: 2),
                      if (c.error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              c.error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: ListView(
                              padding: EdgeInsets.all(desktop ? 32 : 20),
                              children: switch (_page) {
                                0 => _dashboard(context),
                                1 => _nodes(context),
                                2 => _rules(context),
                                _ => _settings(context),
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _page,
                  onDestinationSelected: (index) =>
                      setState(() => _page = index),
                  destinations: [
                    for (var i = 0; i < _titles.length; i++)
                      NavigationDestination(
                        icon: Icon(_icons[i]),
                        label: _titles[i],
                      ),
                  ],
                ),
        );
      },
    ),
  );

  List<Widget> _dashboard(BuildContext context) {
    final active =
        c.status.running ||
        c.state == CoreState.starting ||
        c.state == CoreState.preparing;
    final scheme = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  c.status.running
                      ? Icons.check_circle_outline
                      : Icons.power_settings_new,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stateLabel(c.state),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              '127.0.0.1:${c.status.mixedPort ?? c.mixedPort}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('HTTP / SOCKS5 本地混合代理。请在需要的应用中手动设置代理地址。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: !c.initialized || (c.busy && !active)
                  ? null
                  : () {
                      if (active) {
                        c.stop();
                      } else {
                        c.connect();
                      }
                    },
              icon: Icon(
                active ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(active ? '停止本地代理' : '启动本地代理'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 500
              ? (constraints.maxWidth - 12) / 2
              : (constraints.maxWidth - 36) / 4;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                context,
                width,
                Icons.arrow_upward,
                '本次上传',
                bytesLabel(c.status.upload),
              ),
              _metric(
                context,
                width,
                Icons.arrow_downward,
                '本次下载',
                bytesLabel(c.status.download),
              ),
              _metric(
                context,
                width,
                Icons.link,
                '活动连接',
                '${c.status.connections}',
              ),
              _metric(
                context,
                width,
                Icons.layers_outlined,
                '运行快照',
                '#${c.status.appliedRevision}',
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 28),
      _section(context, '路由模式'),
      Wrap(
        spacing: 8,
        children: [
          for (final mode in RoutingMode.values)
            ChoiceChip(
              label: Text(modeLabel(mode)),
              selected: c.profile.mode == mode,
              onSelected: editable
                  ? (_) => c.save(c.profile.copyWith(mode: mode))
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('模式只影响通过本地代理的请求。切换模式或配置时会重启内核，现有连接将断开。'),
      const SizedBox(height: 28),
      _section(context, '当前配置'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.description_outlined),
        title: Text(c.profile.displayName),
        subtitle: Text(
          '${c.profile.nodes.length} 个节点 · ${c.profile.rules.length} 条规则 · 修订 ${c.profile.revision}',
        ),
      ),
      const Divider(),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline),
        title: Text('当前阶段：普通代理联调'),
        subtitle: Text(
          '系统代理、Windows TUN、Android VPN 和订阅尚未启用。运行状态表示本地监听已就绪，不代表设备流量已被接管。',
        ),
      ),
    ];
  }

  Widget _metric(
    BuildContext context,
    double width,
    IconData icon,
    String label,
    String value,
  ) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: switch (icon) {
              Icons.arrow_upward => const Color(0xff426589),
              Icons.arrow_downward => const Color(0xff357060),
              Icons.link => const Color(0xff75644a),
              _ => const Color(0xff656579),
            },
            size: 20,
          ),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    ),
  );
  Widget _section(BuildContext context, String title, {VoidCallback? add}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (add != null)
              IconButton(
                onPressed: editable ? add : null,
                tooltip: '添加',
                icon: const Icon(Icons.add),
              ),
          ],
        ),
      );

  List<Widget> _nodes(BuildContext context) => [
    _section(context, '代理组 · PROXY', add: () => _editNode()),
    const Text('首版支持无认证 HTTP / SOCKS5 上游节点。节点选择只影响以 PROXY 为目标的请求。'),
    const SizedBox(height: 16),
    _nodeTile(context, null),
    for (final node in c.profile.nodes) _nodeTile(context, node),
    if (c.profile.nodes.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('暂无上游节点。可以添加节点，或使用 DIRECT 验证本地代理链路。'),
      ),
  ];
  Widget _nodeTile(BuildContext context, ProxyNode? node) {
    final id = node?.id ?? directTarget;
    final selected =
        (c.selectedNodeId ?? c.profile.nodes.firstOrNull?.id ?? directTarget) ==
        id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: editable ? () => c.save(c.profile, selection: id) : null,
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
          ),
          title: Text(node?.displayName ?? 'DIRECT · 直连'),
          subtitle: Text(
            node == null
                ? '不经过上游代理'
                : '${node.protocol.name.toUpperCase()} · ${node.server}:${node.port}',
          ),
          trailing: node == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: editable ? () => _editNode(node) : null,
                      tooltip: '编辑节点',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: editable ? () => _deleteNode(node) : null,
                      tooltip: '删除节点',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _editNode([ProxyNode? original]) async {
    final node = await showDialog<ProxyNode>(
      context: context,
      builder: (_) => NodeDialog(node: original),
    );
    if (node == null || !mounted) return;
    final nodes = [...c.profile.nodes];
    final index = nodes.indexWhere((item) => item.id == node.id);
    if (index < 0) {
      nodes.add(node);
    } else {
      nodes[index] = node;
    }
    await c.save(c.profile.copyWith(nodes: nodes));
  }

  Future<void> _deleteNode(ProxyNode node) async {
    if (c.profile.finalTargetId == node.id ||
        c.profile.rules.any((r) => r.targetId == node.id)) {
      _message('该节点仍被规则引用，请先修改对应规则。');
      return;
    }
    if (!await _confirm('删除“${node.displayName}”？')) return;
    await c.save(
      c.profile.copyWith(
        nodes: c.profile.nodes.where((n) => n.id != node.id).toList(),
      ),
    );
  }

  List<Widget> _rules(BuildContext context) => [
    _section(context, '匹配规则', add: () => _editRule()),
    const Text('按下列顺序匹配。仅规则模式使用此列表；排序按钮会即时保存并应用。'),
    const SizedBox(height: 16),
    for (var i = 0; i < c.profile.rules.length; i++) _ruleTile(context, i),
    if (c.profile.rules.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('暂无自定义规则，所有请求按最终规则处理。'),
      ),
    const Divider(),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      key: ValueKey(c.profile.finalTargetId),
      initialValue: c.profile.finalTargetId,
      decoration: const InputDecoration(labelText: '最终规则 · MATCH'),
      isExpanded: true,
      items: [
        for (final target in [
          directTarget,
          rejectTarget,
          proxyTarget,
          ...c.profile.nodes.map((n) => n.id),
        ])
          DropdownMenuItem(
            value: target,
            child: Text(
              targetLabel(target, c.profile),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: editable
          ? (value) => c.save(c.profile.copyWith(finalTargetId: value))
          : null,
    ),
  ];
  Widget _ruleTile(BuildContext context, int index) {
    final rule = c.profile.rules[index];
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Switch(
            value: rule.enabled,
            onChanged: editable
                ? (value) {
                    final rules = [...c.profile.rules];
                    rules[index] = RuleSpec(
                      id: rule.id,
                      kind: rule.kind,
                      value: rule.value,
                      targetId: rule.targetId,
                      enabled: value,
                      noResolve: rule.noResolve,
                    );
                    c.save(c.profile.copyWith(rules: rules));
                  }
                : null,
          ),
          title: Text('${rule.coreType} · ${rule.value}'),
          subtitle: Text(targetLabel(rule.targetId, c.profile)),
          onTap: editable ? () => _editRule(rule) : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '上移',
              icon: const Icon(Icons.arrow_upward),
              onPressed: editable && index > 0
                  ? () => _moveRule(index, -1)
                  : null,
            ),
            IconButton(
              tooltip: '下移',
              icon: const Icon(Icons.arrow_downward),
              onPressed: editable && index + 1 < c.profile.rules.length
                  ? () => _moveRule(index, 1)
                  : null,
            ),
            IconButton(
              tooltip: '编辑规则',
              icon: const Icon(Icons.edit_outlined),
              onPressed: editable ? () => _editRule(rule) : null,
            ),
            IconButton(
              tooltip: '删除规则',
              icon: const Icon(Icons.delete_outline),
              onPressed: editable
                  ? () => c.save(
                      c.profile.copyWith(
                        rules: c.profile.rules
                            .where((r) => r.id != rule.id)
                            .toList(),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }

  void _moveRule(int index, int delta) {
    final rules = [...c.profile.rules];
    final rule = rules.removeAt(index);
    rules.insert(index + delta, rule);
    c.save(c.profile.copyWith(rules: rules));
  }

  Future<void> _editRule([RuleSpec? rule]) async {
    final result = await showDialog<RuleSpec>(
      context: context,
      builder: (_) => RuleDialog(profile: c.profile, rule: rule),
    );
    if (result == null || !mounted) return;
    final rules = [...c.profile.rules];
    final index = rules.indexWhere((r) => r.id == result.id);
    if (index < 0) {
      rules.add(result);
    } else {
      rules[index] = result;
    }
    await c.save(c.profile.copyWith(rules: rules));
  }

  List<Widget> _settings(BuildContext context) => [
    _section(context, '配置文件'),
    Text(c.profile.displayName, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    SelectableText('ID: ${c.profile.id}'),
    const SizedBox(height: 16),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: editable ? _importProfile : null,
          icon: const Icon(Icons.input),
          label: const Text('导入 JSON'),
        ),
        OutlinedButton.icon(
          onPressed: editable
              ? () => _showJson(
                  '导出配置',
                  const JsonEncoder.withIndent('  ')
                      .convert(c.profile.toJson()),
                )
              : null,
          icon: const Icon(Icons.output),
          label: const Text('导出 JSON'),
        ),
        OutlinedButton.icon(
          onPressed: editable
              ? () {
                  try {
                    _showJson(
                      '生成的内核配置',
                      const JsonEncoder.withIndent('  ').convert(
                        jsonDecode(
                          c.compiler
                              .compile(
                                c.profile,
                                mixedPort: c.mixedPort,
                                selectedNodeId: c.selectedNodeId,
                              )
                              .text,
                        ),
                      ),
                    );
                  } catch (error) {
                    _message('$error');
                  }
                }
              : null,
          icon: const Icon(Icons.code),
          label: const Text('查看编译结果'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    const Text('导入 / 导出使用 flvp-profile v1 JSON。支持粘贴和复制，配置中不存放认证信息。'),
    const SizedBox(height: 28),
    _section(context, '本机设置'),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.settings_ethernet),
      title: const Text('本地混合代理端口'),
      subtitle: Text('127.0.0.1:${c.mixedPort}'),
      trailing: IconButton(
        tooltip: '修改端口',
        icon: const Icon(Icons.edit_outlined),
        onPressed: editable ? _editPort : null,
      ),
    ),
    const Divider(),
    const SizedBox(height: 24),
    _section(context, '内核能力'),
    Text(
      c.hostAvailable
          ? 'vp_core ${c.bridge.capabilities?['coreVersion']} · 宿主 ${c.bridge.capabilities?['hostVersion']}'
          : '原生宿主尚未就绪',
    ),
    const SizedBox(height: 8),
    const Text('已接入：本地 HTTP / SOCKS5 监听、基础规则、配置快照、失败回退、真实状态与累计流量。'),
    const SizedBox(height: 12),
    const Text(
      '待接入：系统代理、TUN / VPN、认证节点、订阅、规则集与 DNS 接管。Android 当前通过前台服务维持普通代理。',
    ),
    const SizedBox(height: 24),
    SelectableText(
      '数据目录\n${c.store.root.path}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 16),
    const Text('Windows 退出时停止本实例。Android 返回桌面后继续运行，可在应用或前台服务通知中停止。'),
  ];
  Future<void> _importProfile() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: '导入配置 JSON',
        label: '粘贴 flvp-profile v1',
        multiline: true,
      ),
    );
    if (text == null || !mounted) return;
    try {
      final profile = Profile.fromText(text);
      if (!await _confirm('用“${profile.displayName}”替换当前配置？')) return;
      await c.save(profile, selection: directTarget);
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _editPort() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: '本地代理端口',
        label: '1024–65535',
        initial: '${c.mixedPort}',
      ),
    );
    if (text == null || !mounted) return;
    final port = int.tryParse(text);
    if (port == null || port < 1024 || port > 65535) {
      _message('端口必须为 1024–65535 的整数');
      return;
    }
    await c.save(c.profile, port: port);
  }

  Future<void> _showJson(String title, String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('复制并关闭'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    required this.label,
    this.initial = '',
    this.multiline = false,
  });
  final String title;
  final String label;
  final String initial;
  final bool multiline;
  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: widget.multiline ? 8 : 1,
          maxLines: widget.multiline ? 16 : 1,
          decoration: InputDecoration(labelText: widget.label),
          style: widget.multiline
              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
              : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('确定'),
      ),
    ],
  );
}

class NodeDialog extends StatefulWidget {
  const NodeDialog({super.key, this.node});
  final ProxyNode? node;
  @override
  State<NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<NodeDialog> {
  late final _name = TextEditingController(
    text: widget.node?.displayName ?? '新节点',
  );
  late final _server = TextEditingController(text: widget.node?.server ?? '');
  late final _port = TextEditingController(
    text: '${widget.node?.port ?? 1080}',
  );
  late NodeProtocol _protocol = widget.node?.protocol ?? NodeProtocol.socks5;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.node == null ? '添加节点' : '编辑节点'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<NodeProtocol>(
              initialValue: _protocol,
              decoration: const InputDecoration(labelText: '协议（无认证）'),
              items: [
                for (final protocol in {
                  NodeProtocol.http,
                  NodeProtocol.socks5,
                  if (widget.node != null) widget.node!.protocol,
                })
                  DropdownMenuItem(
                    value: protocol,
                    child: Text(protocol.name.toUpperCase()),
                  ),
              ],
              onChanged: (value) => setState(() => _protocol = value!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _server,
              decoration: const InputDecoration(labelText: '服务器 IP / 域名'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '端口'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final node = ProxyNode(
              id: widget.node?.id ?? const Uuid().v4(),
              displayName: _name.text.trim(),
              protocol: _protocol,
              server: _server.text.trim(),
              port: int.tryParse(_port.text) ?? 0,
              options: widget.node?.protocol == _protocol
                  ? widget.node!.options
                  : const NodeOptions(),
            );
            node.validate();
            Navigator.pop(context, node);
          } catch (error) {
            setState(() => _error = '$error');
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class RuleDialog extends StatefulWidget {
  const RuleDialog({super.key, required this.profile, this.rule});
  final Profile profile;
  final RuleSpec? rule;
  @override
  State<RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<RuleDialog> {
  late final _value = TextEditingController(text: widget.rule?.value ?? '');
  late RuleKind _kind = widget.rule?.kind ?? RuleKind.domainSuffix;
  late String _target = widget.rule?.targetId ?? directTarget;
  late bool _noResolve = widget.rule?.noResolve ?? false;
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.rule == null ? '添加规则' : '编辑规则'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<RuleKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '规则类型'),
              items: [
                for (final kind in RuleKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(
                      RuleSpec(
                        id: '',
                        kind: kind,
                        value: '',
                        targetId: '',
                      ).coreType,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _kind = value!;
                _noResolve = false;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _value,
              decoration: const InputDecoration(
                labelText: '参数',
                helperText: '域名、CIDR、TCP / UDP 或目标端口',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _target,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '目标'),
              items: [
                for (final id in [
                  directTarget,
                  rejectTarget,
                  proxyTarget,
                  ...widget.profile.nodes.map((n) => n.id),
                ])
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      targetLabel(id, widget.profile),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _target = value!),
            ),
            if (_kind == RuleKind.ipCidr)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('no-resolve'),
                value: _noResolve,
                onChanged: (value) => setState(() => _noResolve = value!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final rule = RuleSpec(
              id: widget.rule?.id ?? const Uuid().v4(),
              kind: _kind,
              value: _value.text.trim(),
              targetId: _target,
              noResolve: _noResolve,
              enabled: widget.rule?.enabled ?? true,
            );
            rule.validate();
            Navigator.pop(context, rule);
          } catch (error) {
            setState(() => _error = '$error');
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
