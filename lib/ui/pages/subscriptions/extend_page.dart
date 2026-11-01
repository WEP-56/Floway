import 'dart:async';

import 'package:collection/collection.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../icons/flvp_icon.dart';
import '../../store/store_scope.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';
import '../settings/scripts_page.dart';
import 'profile_rules_page.dart';

/// 配置覆写：标准（附加规则 + 匹配目标）与脚本（选一份覆写脚本）两种模式。
///
/// 与上游 `ExtendView` 同一套状态与动作：`profile.extendType` / `scriptId` /
/// `matchTarget` 写 `profilesProvider`，规则写 `profileRulesProvider`，
/// 「立即应用」调 `setupAction.applyProfile`，离开本页时 `autoApplyProfile`。
class FlvpExtendPage extends ConsumerStatefulWidget {
  const FlvpExtendPage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpExtendPage> createState() => _FlvpExtendPageState();
}

class _FlvpExtendPageState extends ConsumerState<FlvpExtendPage> {
  /// 快速应用也要读得出「应用了一次」，而不是闪一下。
  static const _minApplyingDuration = Duration(milliseconds: 600);

  late final SetupAction _setupAction;
  List<Object?>? _applied;
  var _unappliedOnOpen = false;
  var _applying = false;

  int get _profileId => widget.profileId;

  @override
  void initState() {
    super.initState();
    _setupAction = ref.read(setupActionProvider.notifier);
    ref.listenManual(clashConfigProvider(_profileId), (_, _) {});
    if (ref.read(currentProfileIdProvider) == _profileId) {
      unawaited(_checkUnappliedOnOpen());
    }
  }

  @override
  void dispose() {
    _setupAction.autoApplyProfile();
    super.dispose();
  }

  Future<void> _checkUnappliedOnOpen() async {
    final applied = await _setupAction.inputsApplied();
    if (!applied && mounted) {
      setState(() => _unappliedOnOpen = true);
    }
  }

  List<Object?>? _watchInputs() {
    final profile = ref.watch(
      profileProvider(_profileId).select(
        (state) => (state?.extendType, state?.scriptId, state?.matchTarget),
      ),
    );
    final rules = ref.watch(profileRulesProvider(_profileId)).value;
    final disabledRuleIds = ref
        .watch(profileDisabledRuleIdsProvider(_profileId))
        .value;
    if (rules == null || disabledRuleIds == null) return null;
    return [profile, rules, disabledRuleIds];
  }

  Future<void> _applyNow(List<Object?> inputs) async {
    setState(() => _applying = true);
    try {
      final (applied, _) = await (
        globalState.safeRun(_setupAction.applyProfile),
        Future<void>.delayed(_minApplyingDuration),
      ).wait;
      if (applied != true || !mounted) return;
      _applied = inputs;
      _unappliedOnOpen = false;
      FlvpStoreScope.read(context).notify('已应用当前配置');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _setExtendType(ExtendType type) {
    ref.read(profilesProvider.notifier).updateProfile(_profileId, (state) {
      return state.copyWith(extendType: type);
    });
  }

  void _setScript(int scriptId) {
    ref.read(profilesProvider.notifier).updateProfile(_profileId, (state) {
      return state.copyWith(scriptId: state.scriptId == scriptId ? null : scriptId);
    });
  }

  Future<void> _openRules() async {
    await pushFlvpPage<void>(
      context,
      FlvpProfileRulesPage(profileId: _profileId, platform: widget.platform),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final profile = ref.watch(profileProvider(_profileId));
    final extendType = ref.watch(extendTypeProvider(_profileId));
    final inputs = _watchInputs();
    if (inputs != null) _applied ??= inputs;
    final isCurrent = ref.watch(currentProfileIdProvider) == _profileId;
    final hasChanges =
        isCurrent &&
        inputs != null &&
        (_unappliedOnOpen ||
            !const DeepCollectionEquality().equals(_applied, inputs));
    final rules = ref.watch(profileRulesProvider(_profileId)).value ?? const <Rule>[];
    final matchTarget = profile?.matchTarget;
    final scripts = ref.watch(scriptsProvider).value ?? const <Script>[];
    final scriptId = profile?.scriptId;
    final script = scripts.where((item) => item.id == scriptId).firstOrNull;

    return FlvpPageScaffold(
      title: '覆写',
      subtitle:
          '${profile?.realLabel ?? ''} · ${extendType == ExtendType.standard ? '标准' : '脚本'}',
      actions: [
        if (hasChanges || _applying)
          FlvpButton(
            size: FlvpControlSize.sm,
            label: _applying ? '应用中…' : '立即应用',
            onPressed: _applying || inputs == null
                ? null
                : () => _applyNow(inputs),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlvpSettingsSection(
            title: '覆写模式',
            footer: extendType == ExtendType.standard
                ? '标准模式把这份配置自己追加的规则接在配置末尾。'
                : '脚本模式用一段 JavaScript 覆写运行配置。',
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: FlvpSegmented<ExtendType>(
                  full: true,
                  value: extendType,
                  options: const [
                    FlvpSegmentedOption(ExtendType.standard, '标准'),
                    FlvpSegmentedOption(ExtendType.script, '脚本'),
                  ],
                  onChanged: _setExtendType,
                ),
              ),
            ],
          ),
          if (extendType == ExtendType.standard)
            FlvpSettingsSection(
              title: '标准覆写',
              footer: '离开本页时会自动应用一次；改动当前配置时可以点右上角立即应用。',
              children: [
                FlvpSettingsValue(
                  icon: 'Route',
                  title: '附加规则',
                  subtitle: '按顺序追加到配置末尾',
                  value: rules.isEmpty ? '未添加' : '${rules.length} 条',
                  onTap: _openRules,
                ),
                FlvpSettingsRow(
                  icon: 'Zap',
                  title: '匹配目标',
                  subtitle: '在附加规则页里选择，没有命中任何规则时使用',
                  onTap: _openRules,
                  trailing: Text(
                    matchTarget ?? '跟随配置',
                    style: flvpText(
                      13,
                      weight: FontWeight.w400,
                      color: colors.ink2,
                      mono: true,
                    ),
                  ),
                ),
              ],
            )
          else
            FlvpSettingsSection(
              title: '覆写脚本',
              footer: script == null
                  ? '还没有选择脚本，应用时不会做脚本覆写。'
                  : '当前脚本：${script.label}',
              children: [
                if (scripts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 18,
                    ),
                    child: Text(
                      '还没有脚本，先到「脚本」里创建或导入一份。',
                      style: flvpText(
                        12.5,
                        weight: FontWeight.w400,
                        color: colors.ink3,
                      ),
                    ),
                  )
                else
                  for (final item in scripts)
                    FlvpRow(
                      icon: FlvpIcon(
                        item.id == scriptId ? 'Check' : 'Activity',
                        size: 18,
                        color: item.id == scriptId
                            ? colors.primary
                            : colors.ink2,
                      ),
                      title: item.label,
                      subtitle: item.url != null ? '远程 · 会随脚本同步' : '本地脚本',
                      onTap: () => _setScript(item.id),
                    ),
                FlvpSettingsLink(
                  icon: 'Activity',
                  title: '管理脚本',
                  subtitle: '新增、编辑、导入与同步',
                  onTap: () => pushFlvpPage<void>(
                    context,
                    FlvpScriptsPage(platform: widget.platform),
                  ),
                ),
              ],
            ),
          if (!isCurrent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                spacing: 8,
                children: [
                  FlvpIcon('Info', size: 15, color: colors.ink3),
                  Expanded(
                    child: Text(
                      '这份配置不是当前配置，覆写会在切换过去后生效。',
                      style: flvpText(
                        12,
                        weight: FontWeight.w400,
                        color: colors.ink3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
