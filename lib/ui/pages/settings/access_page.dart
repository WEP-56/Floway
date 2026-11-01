import 'dart:async';

import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/plugins/app.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/motion.dart';
import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/ripple.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';

/// 应用访问控制：白名单 / 黑名单两种模式，按应用决定是否走代理。
///
/// 数据与生效方式沿用上游 `AccessView`：`accessControlStateProvider` 是编辑
/// 中的副本，保存时写回 `vpnSettingProvider.accessControlProps`；应用列表来自
/// `packagesProvider`（`systemActionProvider.getPackages`）。这里补回上游漏掉的
/// 「发起授权」入口：列表为空时无论权限接口怎么答，都先把授权按钮摆出来。
class FlvpAccessPage extends ConsumerStatefulWidget {
  const FlvpAccessPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpAccessPage> createState() => _FlvpAccessPageState();
}

class _FlvpAccessPageState extends ConsumerState<FlvpAccessPage> {
  final TextEditingController _query = TextEditingController();
  var _loading = true;
  var _granting = false;
  String? _error;

  bool get _mobile => widget.platform == FlvpPlatform.mobile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = ref.read(vpnSettingProvider).accessControlProps.copyWith();
      ref.read(accessControlStateProvider.notifier).value = saved;
      unawaited(_loadPackages());
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(systemActionProvider.notifier).getPackages();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '读取应用列表失败：${compactError(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grant() async {
    if (_granting) return;
    setState(() => _granting = true);
    try {
      final granted = await ref
          .read(systemActionProvider.notifier)
          .requestInstalledAppsPermission();
      if (!mounted) return;
      if (granted) {
        await _loadPackages();
        return;
      }
      final ok = await showFlvpConfirm(
        context: context,
        platform: widget.platform,
        title: '还没有拿到权限',
        message: '系统拒绝了「已安装应用」权限。可以到系统设置里为本应用打开它，再回来重试。',
        confirmLabel: '去系统设置',
        cancelLabel: '稍后',
      );
      if (ok == true) await app?.openAppSettings();
    } catch (error) {
      if (mounted) setState(() => _error = '发起授权失败：${compactError(error)}');
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  AccessControlProps _current() => ref.read(accessControlStateProvider);

  /// 只保留当前可见（未被过滤掉）的应用，避免把隐藏的包名也存进去。
  AccessControlProps _normalized(AccessControlProps props) {
    final packages = ref.read(packagesProvider);
    if (packages.isEmpty) return props;
    final visible = packages
        .whereVisible(
          isFilterSystemApp: props.isFilterSystemApp,
          isFilterNonInternetApp: props.isFilterNonInternetApp,
        )
        .map((item) => item.packageName)
        .toSet();
    return props.copyWithNewList(
      props.currentList.where(visible.contains).toList()..sort(),
    );
  }

  void _save() {
    final props = _normalized(_current());
    ref
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(accessControlProps: props));
    FlvpStoreScope.read(context).notify('已保存应用访问控制');
  }

  Future<void> _leave() async {
    if (!_hasChanges()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await showFlvpConfirm(
      context: context,
      platform: widget.platform,
      title: '保存修改',
      message: '应用访问控制有未保存的改动，是否保存？',
      confirmLabel: '保存',
      cancelLabel: '放弃',
    );
    if (!mounted) return;
    if (ok == true) _save();
    Navigator.of(context).pop();
  }

  bool _hasChanges() {
    final saved = ref.read(vpnSettingProvider).accessControlProps;
    return _normalized(saved) != _normalized(_current());
  }

  void _update(AccessControlProps Function(AccessControlProps state) update) {
    ref.read(accessControlStateProvider.notifier).update(update);
  }

  void _toggle(String packageName) {
    _update((state) {
      final list = Set<String>.from(state.currentList)..addOrRemove(packageName);
      return state.copyWithNewList(list.toList());
    });
  }

  Future<void> _pickMode() async {
    final props = _current();
    final next = await showFlvpOptionsPrompt<AccessControlMode>(
      context: context,
      platform: widget.platform,
      title: '模式',
      subtitle: '白名单：只让选中的应用走代理；黑名单：选中的应用不走代理',
      value: props.mode,
      options: const [
        FlvpRadioOption(AccessControlMode.acceptSelected, '白名单'),
        FlvpRadioOption(AccessControlMode.rejectSelected, '黑名单'),
      ],
    );
    if (next == null || next == props.mode) return;
    _update((state) => state.copyWith(mode: next));
  }

  Future<void> _pickSort() async {
    final props = _current();
    final next = await showFlvpOptionsPrompt<AccessSortType>(
      context: context,
      platform: widget.platform,
      title: '排序',
      value: props.sort,
      options: const [
        FlvpRadioOption(AccessSortType.none, '默认'),
        FlvpRadioOption(AccessSortType.name, '按名称'),
        FlvpRadioOption(AccessSortType.time, '按更新时间'),
      ],
    );
    if (next == null || next == props.sort) return;
    _update((state) => state.copyWith(sort: next));
  }

  void _selectAll(List<Package> apps) {
    final names = apps.map((item) => item.packageName).toSet();
    final selected = _current().currentList.toSet();
    _update(
      (state) => state.copyWithNewList(
        selected.containsAll(names) ? const [] : names.toList(),
      ),
    );
  }

  Future<void> _intelligentSelected() async {
    final names = ref
        .read(packagesProvider)
        .map((item) => item.packageName)
        .toList();
    if (names.isEmpty) return;
    final china = (await globalState.loadingRun<List<String>>(() async {
      return await app?.getChinaPackageNames() ?? [];
    }, tag: LoadingTag.access))?.toSet() ?? {};
    if (!mounted) return;
    _update(
      (state) => state.copyWith(
        acceptList: [for (final name in names) if (!china.contains(name)) name],
        rejectList: [for (final name in names) if (china.contains(name)) name],
      ),
    );
  }

  Future<void> _copyList() async {
    await Clipboard.setData(ClipboardData(text: _current().currentList.join('\n')));
    if (mounted) FlvpStoreScope.read(context).notify('已复制选中的应用包名');
  }

  Future<void> _pasteList() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    final list = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (list.isEmpty) return;
    _update((state) => state.copyWithNewList(list.toSet().toList()));
  }

  void _showOptions() {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => Consumer(
        builder: (context, ref, _) {
          final props = ref.watch(accessControlStateProvider);
          void update(AccessControlProps Function(AccessControlProps) fn) {
            ref.read(accessControlStateProvider.notifier).update(fn);
          }

          return FlvpModal(
            platform: widget.platform,
            title: '更多设置',
            subtitle: '模式、过滤与批量操作',
            onClose: host.close,
            child: ListView(
              shrinkWrap: true,
              children: [
                FlvpSettingsSection(
                  title: '模式',
                  children: [
                    FlvpRow(
                      title: '白名单',
                      subtitle: '只让选中的应用走代理',
                      onTap: () {
                        update(
                          (state) => state.copyWith(
                            mode: AccessControlMode.acceptSelected,
                          ),
                        );
                        host.close();
                      },
                      trailing: props.mode == AccessControlMode.acceptSelected
                          ? const FlvpIcon('Check', size: 16)
                          : null,
                    ),
                    FlvpRow(
                      title: '黑名单',
                      subtitle: '选中的应用不走代理',
                      onTap: () {
                        update(
                          (state) => state.copyWith(
                            mode: AccessControlMode.rejectSelected,
                          ),
                        );
                        host.close();
                      },
                      trailing: props.mode == AccessControlMode.rejectSelected
                          ? const FlvpIcon('Check', size: 16)
                          : null,
                    ),
                  ],
                ),
                FlvpSettingsSection(
                  title: '过滤与排序',
                  children: [
                    FlvpSettingsToggle(
                      icon: 'Settings',
                      title: '隐藏系统应用',
                      value: props.isFilterSystemApp,
                      onChanged: (value) => update(
                        (state) => state.copyWith(isFilterSystemApp: value),
                      ),
                    ),
                    FlvpSettingsToggle(
                      icon: 'Globe',
                      title: '隐藏无网络权限的应用',
                      value: props.isFilterNonInternetApp,
                      onChanged: (value) => update(
                        (state) =>
                            state.copyWith(isFilterNonInternetApp: value),
                      ),
                    ),
                    FlvpSettingsValue(
                      icon: 'SlidersHorizontal',
                      title: '排序',
                      value: switch (props.sort) {
                        AccessSortType.none => '默认',
                        AccessSortType.name => '按名称',
                        AccessSortType.time => '按更新时间',
                      },
                      onTap: () {
                        host.close();
                        unawaited(_pickSort());
                      },
                    ),
                  ],
                ),
                FlvpSettingsSection(
                  title: '批量',
                  children: [
                    FlvpSettingsLink(
                      icon: 'Zap',
                      title: '智能选择',
                      subtitle: '把中国应用设为不走代理，其余走代理',
                      onTap: () {
                        host.close();
                        unawaited(_intelligentSelected());
                      },
                    ),
                    FlvpSettingsLink(
                      icon: 'Copy',
                      title: '复制选中包名',
                      onTap: () {
                        host.close();
                        unawaited(_copyList());
                      },
                    ),
                    FlvpSettingsLink(
                      icon: 'ClipboardPaste',
                      title: '从剪贴板导入包名',
                      onTap: () {
                        host.close();
                        unawaited(_pasteList());
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final props = ref.watch(accessControlStateProvider);
    final packages = ref.watch(packagesProvider);
    final keyword = _query.text.trim().toLowerCase();
    final apps = packages
        .getViewList(
          pinedList: props.currentList,
          sortType: props.sort,
          isFilterSystemApp: props.isFilterSystemApp,
          isFilterNonInternetApp: props.isFilterNonInternetApp,
        )
        .where(
          (item) =>
              keyword.isEmpty ||
              item.label.toLowerCase().contains(keyword) ||
              item.packageName.toLowerCase().contains(keyword),
        )
        .toList();
    final selected = props.currentList.toSet();
    final selectedCount = [
      for (final app in apps)
        if (selected.contains(app.packageName)) app.packageName,
    ].length;
    final needsPermission = packages.isEmpty;

    Widget list;
    if (_loading && packages.isEmpty) {
      list = const Center(child: FlvpSpinner(size: 22));
    } else if (packages.isEmpty) {
      list = _permissionPrompt(colors);
    } else if (apps.isEmpty) {
      list = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            FlvpIcon('Search', size: 26, color: colors.ink3),
            Text(
              keyword.isEmpty ? '没有可显示的应用' : '没有匹配的应用',
              style: flvpText(13.5, color: colors.ink3),
            ),
          ],
        ),
      );
    } else {
      list = ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: apps.length,
        itemExtent: 64,
        itemBuilder: (_, index) {
          final app = apps[index];
          return _AppRow(
            package: app,
            selected: selected.contains(app.packageName),
            enabled: props.enable,
            onTap: () => _toggle(app.packageName),
          );
        },
      );
    }

    return PopScope(
      canPop: !_hasChanges(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_leave());
      },
      child: FlvpPageScaffold(
        title: '应用访问控制',
        subtitle: '${packages.length} 个应用 · 已选 $selectedCount',
        scrollable: false,
        actions: [
          FlvpIconButton(
            label: '更多设置',
            dimension: 40,
            onPressed: _showOptions,
            icon: const FlvpIcon('SlidersHorizontal', size: 19),
          ),
          if (_hasChanges())
            FlvpButton(
              size: FlvpControlSize.sm,
              label: '保存',
              onPressed: _save,
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: FlvpSettingsSection(
                title: '状态',
                children: [
                  FlvpSettingsToggle(
                    icon: 'Settings',
                    title: '启用访问控制',
                    subtitle: props.mode == AccessControlMode.acceptSelected
                        ? '白名单：只让选中的应用走代理'
                        : '黑名单：选中的应用不走代理',
                    value: props.enable,
                    onChanged: (value) =>
                        _update((state) => state.copyWith(enable: value)),
                  ),
                  FlvpSettingsValue(
                    icon: 'SlidersHorizontal',
                    title: '模式',
                    value: props.mode == AccessControlMode.acceptSelected
                        ? '白名单'
                        : '黑名单',
                    onTap: _pickMode,
                  ),
                  if (needsPermission)
                    FlvpSettingsRow(
                      icon: 'TriangleAlert',
                      title: '还没有应用列表',
                      subtitle: '需要先授权读取已安装的应用',
                      trailing: FlvpButton(
                        size: FlvpControlSize.sm,
                        label: _granting ? '授权中…' : '发起授权',
                        onPressed: _granting ? null : _grant,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _SearchBar(
                controller: _query,
                onChanged: (_) => setState(() {}),
                onSelectAll: apps.isEmpty ? null : () => _selectAll(apps),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  _error!,
                  style: flvpText(12, weight: FontWeight.w400, color: colors.warn),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: list,
              ),
            ),
            if (_mobile) const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _permissionPrompt(FlvpColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            FlvpIcon('TriangleAlert', size: 26, color: colors.warn),
            Text('还没有读取到应用列表', style: flvpText(14, color: colors.ink)),
            Text(
              '部分系统需要单独授权「已安装应用」，授权后这里会列出可代理的应用。',
              textAlign: TextAlign.center,
              style: flvpText(12.5, weight: FontWeight.w400, color: colors.ink3),
            ),
            FlvpButton(
              label: _granting ? '授权中…' : '发起授权',
              icon: const FlvpIcon('Check', size: 16),
              onPressed: _granting ? null : _grant,
            ),
            FlvpButton(
              variant: FlvpButtonVariant.text,
              label: '重新读取',
              onPressed: _loading ? null : _loadPackages,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.package,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Package package;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: FlvpHover(
        builder: (context, hovered) => FlvpRipple(
          color: colors.ink,
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: FlvpMotion.hover,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: hovered ? colors.surf2 : colors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: FlvpElevation.card,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PackageIcon(
                      packageName: package.packageName,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Text(
                          package.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: flvpText(13.5, color: colors.ink),
                        ),
                        Text(
                          package.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: flvpText(
                            11.5,
                            weight: FontWeight.w400,
                            color: colors.ink3,
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CheckBox(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return AnimatedContainer(
      duration: FlvpMotion.control,
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : const Color(0x00000000),
        border: Border.all(
          color: selected ? colors.primary : colors.ink3,
          width: 2,
        ),
      ),
      child: selected
          ? FlvpIcon('Check', size: 13, strokeWidth: 3, color: colors.onprimary)
          : null,
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onSelectAll,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Container(
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
                    controller: controller,
                    onChanged: onChanged,
                    style: flvpText(13.5, color: colors.ink),
                    cursorColor: colors.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '搜索应用名称或包名',
                      hintStyle: flvpText(13.5, color: colors.ink3),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: FlvpIcon('X', size: 15, color: colors.ink3),
                  ),
              ],
            ),
          ),
        ),
        FlvpIconButton(
          label: '全选 / 取消全选',
          dimension: 40,
          onPressed: onSelectAll,
          icon: const FlvpIcon('Check', size: 18),
        ),
      ],
    );
  }
}
