import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:floway/common/common.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/inherited.dart';
import 'package:floway/views/profiles/custom/dialers.dart';
import 'package:floway/views/profiles/custom/groups.dart';
import 'package:floway/views/profiles/custom/providers.dart';
import 'package:floway/views/profiles/custom/rules.dart';
import 'package:floway/views/profiles/edit.dart' show renameProfile;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../store/store_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/data_display.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/upstream_page.dart';
import 'preview_page.dart';
import 'profile_override_pages.dart';

/// 自定义工作区：一份自定义配置的分区总览。
///
/// 分区与动作沿用上游 `CustomProfileView`（规则 / 服务提供者 / DNS / 更多，
/// 策略组列表直接复用上游 `CustomProxyGroupsSection`），外壳、概览与
/// 单份配置的 DNS / NTP / 嗅探 / TUN 覆写换成 Floway 版式。
class FlvpCustomProfilePage extends ConsumerStatefulWidget {
  const FlvpCustomProfilePage({
    super.key,
    required this.profileId,
    required this.platform,
    this.isNew = false,
  });

  final int profileId;
  final FlvpPlatform platform;

  /// 新建后没动过的配置，离开时会被丢弃（与上游一致）。
  final bool isNew;

  @override
  ConsumerState<FlvpCustomProfilePage> createState() =>
      _FlvpCustomProfilePageState();
}

class _FlvpCustomProfilePageState extends ConsumerState<FlvpCustomProfilePage> {
  late final SetupAction _setupAction;
  late final ProfilesAction _profilesAction;
  late final Profile? _initialProfile;

  var _discarded = false;
  var _discardOnDispose = false;
  var _loaded = false;
  List<Object?>? _loadedInputs;
  var _edited = false;
  var _importing = false;

  int get _profileId => widget.profileId;

  @override
  void initState() {
    super.initState();
    _setupAction = ref.read(setupActionProvider.notifier);
    _profilesAction = ref.read(profilesActionProvider.notifier);
    _initialProfile = ref.read(profileProvider(_profileId));
  }

  bool get _isUntouched {
    if (!_loaded) return true;
    final profile = ref.read(profileProvider(_profileId));
    return profile != null &&
        profile.label == _initialProfile?.label &&
        profile.overrides == const ProfileOverrides() &&
        ref.read(proxyGroupsProvider(_profileId)).value?.isEmpty == true &&
        ref.read(profileRulesProvider(_profileId)).value?.isEmpty == true;
  }

  List<Object?> get _inputs => [
    ref.read(profileProvider(_profileId)),
    ref.read(customProfileDataProvider(_profileId)),
    ref.read(profileRulesProvider(_profileId)).value,
  ];

  bool get _isEmpty {
    return ref.read(profileProvider(_profileId))?.overrides ==
            const ProfileOverrides() &&
        ref.read(proxyGroupsProvider(_profileId)).value?.isEmpty == true &&
        ref.read(profileRulesProvider(_profileId)).value?.isEmpty == true &&
        ref.read(proxyDialersProvider(_profileId)).value?.isEmpty == true;
  }

  void _openUpstream(Widget view) {
    unawaited(
      pushFlvpPage<void>(
        context,
        ProfileIdProvider(
          profileId: _profileId,
          child: FlvpUpstreamPage(child: view),
        ),
      ),
    );
  }

  void _openRules() => _openUpstream(CustomRulesView(_profileId));

  void _openProviders() => _openUpstream(CustomProvidersView(_profileId));

  void _openDns() {
    unawaited(
      pushFlvpPage<void>(
        context,
        FlvpProfileDnsPage(profileId: _profileId, platform: widget.platform),
      ),
    );
  }

  void _openMore() {
    unawaited(
      pushFlvpPage<void>(
        context,
        FlvpCustomMorePage(profileId: _profileId, platform: widget.platform),
      ),
    );
  }

  void _handlePreview() {
    final profile = ref.read(profileProvider(_profileId));
    if (profile == null) return;
    unawaited(
      pushFlvpPage<void>(
        context,
        FlvpPreviewPage(platform: widget.platform, profile: profile),
      ),
    );
  }

  void _handleRename() {
    final profile = ref.read(profileProvider(_profileId));
    if (profile == null) return;
    unawaited(renameProfile(context, ref, profile));
  }

  Future<void> _chooseImport() async {
    final choice = await showFlvpOptionsPrompt<String>(
      context: context,
      platform: widget.platform,
      title: '导入配置',
      subtitle: '导入会替换当前工作区里的规则、策略组与覆写',
      value: 'url',
      options: const [
        FlvpRadioOption('url', '从地址导入'),
        FlvpRadioOption('file', '从文件导入'),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'url') {
      await _importFromUrl();
    } else {
      await _importFromFile();
    }
  }

  Future<void> _importFromUrl() async {
    final url = await showFlvpTextPrompt(
      context: context,
      platform: widget.platform,
      title: '从地址导入',
      placeholder: 'https://',
      validator: (value) {
        final uri = Uri.tryParse(value);
        return (value.isEmpty || uri == null || !uri.isAbsolute)
            ? '请输入有效的地址'
            : null;
      },
    );
    if (url == null || !mounted) return;
    await _import(() async {
      final response = await request.getFileResponseForUrl(url);
      return decompressUnlabeled(response.data ?? Uint8List(0));
    });
  }

  Future<void> _importFromFile() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null || !mounted) return;
    await _import(file.readBytes);
  }

  Future<void> _import(Future<Uint8List> Function() readBytes) async {
    setState(() => _importing = true);
    try {
      final config = await globalState.safeRun(
        () async => _profilesAction.readCustomImport(_profileId, await readBytes()),
        silence: false,
        title: '导入',
      );
      if (config == null || !mounted) return;
      if (!_isEmpty) {
        final ok = await showFlvpConfirm(
          context: context,
          platform: widget.platform,
          title: '替换工作区',
          message: '导入的配置会替换当前工作区里的规则、策略组与覆写，确定继续吗？',
          confirmLabel: '替换',
          danger: true,
        );
        if (ok != true || !mounted) return;
      }
      await _profilesAction.importCustomProfile(_profileId, config);
      if (!mounted) return;
      if (config.droppedSubRules > 0) {
        FlvpStoreScope.read(context).notify(
          currentAppLocalizations.customImportDroppedSubRules(
            config.droppedSubRules,
            config.droppedSubRules.compact,
          ),
        );
      } else {
        FlvpStoreScope.read(context).notify('已导入配置');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _leave() async {
    final profile = ref.read(profileProvider(_profileId));
    if (profile != null &&
        profile.label == _initialProfile?.label &&
        !_isUntouched) {
      await renameProfile(context, ref, profile, selectAll: true);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 退场动画开始时就算，这样退回去的列表已经不再列这份配置。
  void _discardIfUntouched() {
    if (_discarded || !widget.isNew || !_isUntouched) return;
    _discarded = true;
    unawaited(_profilesAction.deleteProfile(_profileId));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final label = ref.watch(
      profileProvider(_profileId).select(
        (state) => state?.realLabel ?? _initialProfile?.realLabel ?? '',
      ),
    );
    _loaded =
        _loaded ||
        (ref.watch(
              customProfileDataProvider(
                _profileId,
              ).select((state) => state != null),
            ) &&
            !ref.watch(
              profileRulesProvider(
                _profileId,
              ).select((state) => state.isLoading),
            ));
    if (_loaded) _loadedInputs ??= _inputs;
    final groupCount = ref.watch(profileGroupsCountProvider(_profileId)).value;

    return PopScope(
      canPop: !widget.isNew,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _discardIfUntouched();
          return;
        }
        unawaited(_leave());
      },
      child: ProfileIdProvider(
        profileId: _profileId,
        child: FlvpPageScaffold(
          title: label,
          subtitle: _importing
              ? '正在导入…'
              : '自定义配置 · ${groupCount ?? 0} 个策略组',
          scrollable: false,
          actions: [
            FlvpIconButton(
              label: '重命名',
              dimension: 40,
              onPressed: _handleRename,
              icon: const FlvpIcon('Pencil', size: 19),
            ),
            FlvpIconButton(
              label: '运行配置',
              dimension: 40,
              onPressed: _handlePreview,
              icon: const FlvpIcon('Eye', size: 19),
            ),
            FlvpIconButton(
              label: '导入',
              dimension: 40,
              onPressed: _importing || !_loaded ? null : _chooseImport,
              icon: const FlvpIcon('Download', size: 19),
            ),
          ],
          child: !_loaded
              ? const Center(child: FlvpSpinner(size: 22))
              : FlvpUpstreamPage(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: _overview(colors),
                        ),
                      ),
                      CustomProxyGroupsSection(_profileId),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _overview(FlvpColors colors) {
    final rules = ref.watch(profileRulesProvider(_profileId)).value ?? const <Rule>[];
    final issues = ref.watch(customProfileIssuesProvider(_profileId));
    final ruleIssues = issues.rules.length;
    final referenced = referencedProviders(ref, _profileId);
    final data = ref.watch(customProfileDataProvider(_profileId));
    final providerTotal = referenced.proxy.length + referenced.rule.length;
    final missingProviders = data == null
        ? 0
        : [
            for (final name in referenced.proxy)
              if (!data.proxyProviders.contains(name)) name,
            for (final name in referenced.rule)
              if (!data.ruleProviders.contains(name)) name,
          ].length;
    final overrides =
        ref.watch(profileProvider(_profileId).select((state) => state?.overrides)) ??
        const ProfileOverrides();
    final dnsIssues = issues.dns.length;
    final dialerIssues = issues.dialers.length;
    final ntpIssues = issues.ntp.length;
    final dialerCount = ref.watch(
      customProfileDataProvider(_profileId).select(
        (state) => state == null
            ? 0
            : state.dialers.keys.where(state.namedProxies.contains).length,
      ),
    );
    final moreInEffect = [
      dialerCount > 0,
      overrides.customNtpEnabled,
      overrides.customSnifferEnabled,
      widget.platform == FlvpPlatform.pc && overrides.tunOverrideKeys.isNotEmpty,
    ].where((inEffect) => inEffect).length;
    final issueCount =
        issues.proxyGroups.length +
        ruleIssues +
        dialerIssues +
        dnsIssues +
        ntpIssues;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issueCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                FlvpIcon('TriangleAlert', size: 18, color: colors.warn),
                Expanded(
                  child: Text(
                    currentAppLocalizations.customIssuesSummary(issueCount),
                    style: flvpText(
                      12.5,
                      weight: FontWeight.w400,
                      color: colors.warn,
                    ),
                  ),
                ),
              ],
            ),
          ),
        FlvpSettingsSection(
          title: '配置概览',
          children: [
            FlvpSettingsValue(
              icon: 'Route',
              title: '规则',
              subtitle: '按顺序匹配，未命中交给匹配目标',
              value: ruleIssues == 0 ? '${rules.length} 条' : '$ruleIssues / ${rules.length}',
              onTap: _openRules,
            ),
            FlvpSettingsValue(
              icon: 'Server',
              title: '服务提供者',
              subtitle: '引用到的代理集与规则集',
              value: missingProviders == 0
                  ? '$providerTotal 个'
                  : '$missingProviders / $providerTotal',
              onTap: _openProviders,
            ),
            FlvpSettingsValue(
              icon: 'Globe',
              title: 'DNS',
              subtitle: '这份配置自己的 DNS 设置',
              value: dnsIssues > 0
                  ? '$dnsIssues 项待修'
                  : (overrides.customDnsEnabled ? '已启用' : '未启用'),
              onTap: _openDns,
            ),
            FlvpSettingsValue(
              icon: 'SlidersHorizontal',
              title: '更多',
              subtitle: '拨号代理 / NTP / 嗅探 / TUN',
              value: moreInEffect > 0 ? '$moreInEffect 项生效' : '默认',
              onTap: _openMore,
            ),
          ],
        ),
      ],
    );
  }

  @override
  void deactivate() {
    _discardOnDispose = !_discarded && widget.isNew && _isUntouched;
    _edited =
        _loadedInputs != null &&
        !const DeepCollectionEquality().equals(_loadedInputs, _inputs);
    super.deactivate();
  }

  @override
  void dispose() {
    if (_discardOnDispose) {
      final profileId = _profileId;
      // 卸载时 provider 不能再改状态，推到下一轮事件循环。
      unawaited(Future(() => _profilesAction.deleteProfile(profileId)));
    } else if (!_discarded && _edited) {
      final profileId = _profileId;
      scheduleMicrotask(() {
        _profilesAction.touchProfile(profileId);
        _setupAction.autoApplyProfile();
      });
    }
    super.dispose();
  }
}

/// 自定义工作区的「更多」：拨号代理、NTP、嗅探与 TUN。
class FlvpCustomMorePage extends ConsumerWidget {
  const FlvpCustomMorePage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides =
        ref.watch(profileProvider(profileId).select((state) => state?.overrides)) ??
        const ProfileOverrides();
    final issues = ref.watch(customProfileIssuesProvider(profileId));
    final dialerCount = ref.watch(
      customProfileDataProvider(profileId).select(
        (state) => state == null
            ? 0
            : state.dialers.keys.where(state.namedProxies.contains).length,
      ),
    );
    final showsTun = platform == FlvpPlatform.pc;

    void open(Widget page) => unawaited(pushFlvpPage<void>(context, page));

    return FlvpPageScaffold(
      title: '更多',
      subtitle: '拨号代理 / NTP / 嗅探 / TUN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '分区',
            children: [
              FlvpSettingsLink(
                icon: 'Network',
                title: '拨号代理',
                subtitle: dialerCount > 0 ? '$dialerCount 个代理走拨号' : '未使用',
                onTap: () => unawaited(
                  pushFlvpPage<void>(
                    context,
                    ProfileIdProvider(
                      profileId: profileId,
                      child: FlvpUpstreamPage(
                        child: CustomProxyDialersView(profileId),
                      ),
                    ),
                  ),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Timer',
                title: 'NTP',
                subtitle: '这份配置自己的时间同步设置',
                value: issues.ntp.isNotEmpty
                    ? '${issues.ntp.length} 项待修'
                    : (overrides.customNtpEnabled ? '已启用' : '未启用'),
                onTap: () => open(
                  FlvpProfileNtpPage(profileId: profileId, platform: platform),
                ),
              ),
              FlvpSettingsValue(
                icon: 'Eye',
                title: '域名嗅探',
                subtitle: '从 TLS / HTTP 里还原目标域名',
                value: overrides.customSnifferEnabled ? '已启用' : '未启用',
                onTap: () => open(
                  FlvpProfileSnifferPage(profileId: profileId, platform: platform),
                ),
              ),
              if (showsTun)
                FlvpSettingsValue(
                  icon: 'Power',
                  title: 'TUN',
                  subtitle: '这份配置自己的 TUN 设置',
                  value: overrides.tunOverrideKeys.isEmpty
                      ? '默认'
                      : '${overrides.tunOverrideKeys.length} 项',
                  onTap: () => open(
                    FlvpProfileTunPage(profileId: profileId, platform: platform),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              '这些分区都只作用于当前这份自定义配置，不会改动全局设置。',
              style: flvpText(
                12,
                weight: FontWeight.w400,
                color: FlvpThemeScope.colorsOf(context).ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
