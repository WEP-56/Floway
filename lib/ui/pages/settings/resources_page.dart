import 'dart:async';
import 'dart:io';

import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' hide context;

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';

/// 资源更新：Geo 数据、图标集、规则 Provider 与远程脚本的同步与自动更新设置。
/// 同步动作、进度键与失败汇报全部沿用上游 `resourcesActionProvider` /
/// `geoResourceActionProvider`，这里只是把列表换成 Floway 的卡片行。
class FlvpResourcesPage extends ConsumerStatefulWidget {
  const FlvpResourcesPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpResourcesPage> createState() => _FlvpResourcesPageState();
}

class _FlvpResourcesPageState extends ConsumerState<FlvpResourcesPage> {
  final Map<String, FileInfo?> _fileInfos = {};
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFileInfos());
  }

  Future<void> _loadFileInfos() async {
    await Future.wait<Object>([
      ref.read(iconSetsProvider.future),
      ref.read(clashProvidersProvider.future),
      ref.read(scriptsProvider.future),
    ]).catchError((Object _) => const <Object>[]);
    if (!mounted) return;
    final loads = <String, Future<FileInfo?>>{
      for (final type in GeoResource.values) type.updatingKey: _geoFileInfo(type),
      for (final provider in _ruleProviders)
        provider.updatingKey: provider.fileInfo,
      for (final script in _scripts) script.updatingKey: script.fileInfo,
    };
    final infos = await Future.wait([
      for (final load in loads.values) load.catchError((Object _) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _fileInfos
        ..clear()
        ..addAll(Map.fromIterables(loads.keys, infos));
      _loaded = true;
    });
  }

  List<IconSet> get _iconSets => [
    for (final set in ref.read(iconSetsProvider).value ?? const <IconSet>[])
      if (set.isRemote) set,
  ];

  List<ClashProvider> get _ruleProviders => [
    for (final item
        in ref.read(clashProvidersProvider).value ?? const <ClashProvider>[])
      if (item.isRemote) item,
  ];

  List<Script> get _scripts => [
    for (final item in ref.read(scriptsProvider).value ?? const <Script>[])
      if (item.url != null) item,
  ];

  void _toast(String message) => FlvpStoreScope.read(context).notify(message);

  Future<void> _updateAll() async {
    final failures = await ref.read(resourcesActionProvider.notifier).updateAll();
    if (!mounted) return;
    if (failures.isEmpty) {
      _toast('全部资源已更新');
      return;
    }
    final names = failures.map((item) => item.label).join('、');
    _toast('${failures.length} 项更新失败：$names');
  }

  Future<void> _editGeoUrl(GeoResource type) async {
    final url = ref.read(
      patchClashConfigProvider.select((state) => state.geoXUrl[type]),
    );
    final next = await showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '${type.name} 地址',
      subtitle: '留空则用默认地址',
      value: url ?? '',
      placeholder: defaultGeoXUrl[type] ?? 'https://',
    );
    if (next == null || !mounted) return;
    try {
      ref
          .read(geoResourceActionProvider.notifier)
          .updateGeoResourceUrl(type, next.trim());
    } catch (error) {
      _toast('地址无法使用：$error');
    }
  }

  Future<void> _editInterval() async {
    final current = ref.read(
      patchClashConfigProvider.select((state) => state.geoUpdateInterval),
    );
    final next = await showFlvpNumberPrompt(
      context: context,
      platform: widget.platform,
      title: '更新间隔',
      subtitle: '自动更新检查间隔',
      value: current,
      suffix: '小时',
      min: 1,
    );
    if (next == null || next == current || next <= 0) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(geoUpdateInterval: next));
  }

  void _setAutoUpdate(bool value) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(geoAutoUpdate: value));
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _toast('已复制地址');
  }

  @override
  Widget build(BuildContext context) {
    final autoUpdate = ref.watch(
      patchClashConfigProvider.select((state) => state.geoAutoUpdate),
    );
    final interval = ref.watch(
      patchClashConfigProvider.select((state) => state.geoUpdateInterval),
    );
    final iconSets = _iconSets;
    final ruleProviders = _ruleProviders;
    final scripts = _scripts;
    final keys = [
      for (final type in GeoResource.values) type.updatingKey,
      for (final set in iconSets) set.updatingKey,
      for (final provider in ruleProviders) provider.updatingKey,
      for (final script in scripts) script.updatingKey,
    ];
    final busy = ref.watch(
      updatingKeysProvider.select((active) => active.any(keys.contains)),
    );
    final total =
        GeoResource.values.length +
        iconSets.length +
        ruleProviders.length +
        scripts.length;

    return FlvpPageScaffold(
      title: '资源更新',
      subtitle: '$total 项可更新资源',
      actions: [
        FlvpIconButton(
          label: '全部更新',
          dimension: 40,
          onPressed: busy ? null : _updateAll,
          icon: busy
              ? const FlvpSpinner(size: 18)
              : const FlvpIcon('RefreshCw', size: 19),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '自动更新',
            children: [
              FlvpSettingsToggle(
                icon: 'Timer',
                title: '自动更新资源',
                subtitle: '按间隔检查图标、规则与脚本',
                value: autoUpdate,
                onChanged: _setAutoUpdate,
              ),
              if (autoUpdate)
                FlvpSettingsValue(
                  icon: 'CalendarClock',
                  title: '更新间隔',
                  value: '$interval 小时',
                  onTap: _editInterval,
                ),
            ],
          ),
          FlvpSettingsSection(
            title: 'Geo 数据',
            footer: 'Geo 文件由内核自己下载，这里只触发更新与改地址',
            children: [
              for (final type in GeoResource.values)
                _row(
                  key: type.updatingKey,
                  title: type.name,
                  url: ref.watch(
                    patchClashConfigProvider.select((state) => state.geoXUrl[type]),
                  ),
                  onEdit: () => _editGeoUrl(type),
                  onSync: () => ref
                      .read(geoResourceActionProvider.notifier)
                      .updateGeoResource(type),
                ),
            ],
          ),
          if (iconSets.isNotEmpty)
            FlvpSettingsSection(
              title: '图标集',
              children: [
                for (final set in iconSets)
                  _row(
                    key: set.updatingKey,
                    title: set.name,
                    url: set.url,
                    time: set.lastUpdateTime,
                    onSync: () => ref
                        .read(resourcesActionProvider.notifier)
                        .updateIconSet(set),
                  ),
              ],
            ),
          if (ruleProviders.isNotEmpty)
            FlvpSettingsSection(
              title: '规则 Provider',
              children: [
                for (final provider in ruleProviders)
                  _row(
                    key: provider.updatingKey,
                    title: provider.label,
                    url: provider.url,
                    onSync: () => ref
                        .read(resourcesActionProvider.notifier)
                        .updateRuleProvider(provider),
                  ),
              ],
            ),
          if (scripts.isNotEmpty)
            FlvpSettingsSection(
              title: '脚本',
              children: [
                for (final script in scripts)
                  _row(
                    key: script.updatingKey,
                    title: script.label,
                    url: script.url,
                    time: script.lastUpdateTime,
                    onSync: () => ref
                        .read(resourcesActionProvider.notifier)
                        .updateScript(script),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FlvpButton(
              variant: FlvpButtonVariant.tonal,
              label: busy ? '正在更新…' : '更新全部资源',
              icon: const FlvpIcon('RefreshCw', size: 16),
              onPressed: busy ? null : _updateAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String key,
    required String title,
    String? url,
    DateTime? time,
    VoidCallback? onEdit,
    required Future<void> Function() onSync,
  }) {
    final colors = FlvpThemeScope.colorsOf(context);
    final updating = ref.watch(isUpdatingProvider(key));
    final info = _fileInfos[key];
    final size = info?.size.traffic.show;
    final parts = [
      if ((url ?? '').isNotEmpty) '远程',
      if (!_loaded) '读取中' else ?size,
      ?time?.getLastUpdateTimeDesc(context, compact: true),
    ];
    return FlvpSettingsRow(
      icon: 'Archive',
      title: title,
      subtitle: parts.isEmpty ? '未更新过' : parts.join(' · '),
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (updating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: FlvpSpinner(size: 16),
            )
          else ...[
            if ((url ?? '').isNotEmpty)
              FlvpIconButton(
                label: '复制地址',
                dimension: 32,
                onPressed: () => _copyLink(url!),
                icon: FlvpIcon('Copy', size: 15, color: colors.ink3),
              ),
            FlvpIconButton(
              label: '同步 $title',
              dimension: 32,
              onPressed: () => globalState.safeRun(onSync, title: title),
              icon: const FlvpIcon('RefreshCw', size: 15),
            ),
          ],
        ],
      ),
    );
  }
}

Future<FileInfo?> _geoFileInfo(GeoResource type) async {
  final fileName = switch (type) {
    GeoResource.MMDB => MMDB,
    GeoResource.ASN => ASN,
    GeoResource.GEOIP => GEOIP,
    GeoResource.GEOSITE => GEOSITE,
  };
  final homePath = await appPath.homeDirPath;
  return File(join(homePath, fileName)).getFileInfo();
}
