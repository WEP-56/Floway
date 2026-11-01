import 'dart:async';

import 'package:floway/common/app_localizations.dart';
import 'package:floway/common/dialog.dart';
import 'package:floway/common/picker.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/views/profiles/custom/custom.dart';
import 'package:floway/views/profiles/edit.dart';
import 'package:floway/views/profiles/extend/extend.dart';
import 'package:floway/views/profiles/preview.dart';
import 'package:floway/views/profiles/profiles.dart'
    show ReorderableProfilesSheet;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/upstream_page.dart';

/// pages/Subscriptions.tsx — 配置列表。
///
/// 数据与动作全部来自上游：`profilesProvider` / `currentProfileIdProvider`
/// 提供列表与当前配置，`profilesActionProvider` 承担更新、删除与排序，
/// 编辑/覆写/自定义工作区/运行配置直接打开上游既有页面。
class FlvpSubscriptionsPage extends ConsumerStatefulWidget {
  const FlvpSubscriptionsPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpSubscriptionsPage> createState() =>
      _FlvpSubscriptionsPageState();
}

class _FlvpSubscriptionsPageState extends ConsumerState<FlvpSubscriptionsPage> {
  bool _updatingAll = false;

  bool get _mobile => widget.platform == FlvpPlatform.mobile;

  Future<void> _updateAll(List<Profile> profiles) async {
    if (_updatingAll) return;
    final targets = [
      for (final profile in profiles)
        if (profile.type == ProfileType.url) profile,
    ];
    final store = FlvpStoreScope.read(context);
    if (targets.isEmpty) {
      store.notify('没有可更新的远程配置');
      return;
    }
    setState(() => _updatingAll = true);
    final action = ref.read(profilesActionProvider.notifier);
    final failures = <UpdatingMessage>[];
    try {
      await Future.wait([
        for (final profile in targets)
          () async {
            try {
              await action.updateProfile(profile, showLoading: true);
            } catch (error) {
              failures.add(
                UpdatingMessage(
                  label: profile.realLabel,
                  message: userFacingErrorMessage(error, currentAppLocalizations),
                ),
              );
            }
          }(),
      ]);
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      store.notify('${targets.length} 份配置已更新');
    } else {
      store.notify('${failures.length} 份配置更新失败');
      dialogs.showFailures(failures);
    }
  }

  void _openSort(List<Profile> profiles) {
    unawaited(
      openFlvpUpstreamPage(context, ReorderableProfilesSheet(profiles: profiles)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final profiles = ref.watch(profilesProvider);
    final currentProfileId = ref.watch(currentProfileIdProvider);

    if (profiles.isEmpty) {
      return FlvpCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FlvpIcon('Rss', size: 24, color: colors.ink2),
            ),
            Text('暂无配置', style: flvpText(14.5, color: colors.ink)),
            Text(
              _mobile ? '点击右下角「添加配置」开始' : '点击右上角「添加配置」开始',
              textAlign: TextAlign.center,
              style: flvpText(
                12.5,
                weight: FontWeight.w400,
                color: colors.ink3,
              ),
            ),
          ],
        ),
      );
    }

    final cards = [
      for (final profile in profiles)
        _ProfileCard(
          key: ValueKey(profile.id),
          profile: profile,
          active: profile.id == currentProfileId,
          platform: widget.platform,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _mobile ? 12 : 16,
      children: [
        _toolbar(colors, profiles),
        LayoutBuilder(
          builder: (context, constraints) {
            // pc: gap-4 @3xl:grid-cols-2; mobile: single column, gap-3.
            if (_mobile || constraints.maxWidth < 768) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _mobile ? 12 : 16,
                children: cards,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                for (var i = 0; i < cards.length; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        Expanded(child: cards[i]),
                        Expanded(
                          child: i + 1 < cards.length
                              ? cards[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _toolbar(FlvpColors colors, List<Profile> profiles) {
    final remote = profiles.where((p) => p.type == ProfileType.url).length;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$remote 份远程 · ${profiles.length - remote} 份本地/自定义',
            style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
          ),
        ),
        FlvpIconButton(
          label: '更新全部远程配置',
          dimension: 38,
          onPressed: _updatingAll ? null : () => _updateAll(profiles),
          icon: FlvpSpin(
            active: _updatingAll,
            child: const FlvpIcon('RefreshCw', size: 18),
          ),
        ),
        FlvpIconButton(
          label: '排序',
          dimension: 38,
          onPressed: () => _openSort(profiles),
          icon: const FlvpIcon('SlidersHorizontal', size: 18),
        ),
      ],
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _stampText(DateTime? value) => value == null
    ? '未更新'
    : '${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';

String _sizeText(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

String _dateText(DateTime? value) => value == null
    ? '—'
    : '${value.year}-${_two(value.month)}-${_two(value.day)}';

int _daysLeft(DateTime? expire) {
  if (expire == null) return 1 << 30;
  // 向上取整：还差 19 天 23 小时也算“20 天后到期”。
  return (expire.difference(DateTime.now()).inMilliseconds / 86400000).ceil();
}

String _typeLabel(ProfileType type) => switch (type) {
  ProfileType.url => '远程',
  ProfileType.file => '本地',
  ProfileType.custom => '自定义',
};

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.active,
    required this.platform,
  });

  final Profile profile;
  final bool active;
  final FlvpPlatform platform;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _menu;
  bool _busy = false;

  Profile get _profile => widget.profile;

  @override
  void dispose() {
    _menu?.remove();
    _menu?.dispose();
    super.dispose();
  }

  void _toast(String message) => FlvpStoreScope.read(context).notify(message);

  void _closeMenu() {
    _menu?.remove();
    _menu?.dispose();
    _menu = null;
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _toast('操作失败：${userFacingErrorMessage(error, currentAppLocalizations)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() => _run(() async {
    await ref
        .read(profilesActionProvider.notifier)
        .updateProfile(_profile, showLoading: true);
    if (mounted) _toast('「${_profile.realLabel}」已更新');
  });

  void _edit() {
    if (_profile.type == ProfileType.custom) {
      unawaited(
        openFlvpUpstreamPage(
          context,
          CustomProfileView(profileId: _profile.id),
        ),
      );
      return;
    }
    unawaited(
      openFlvpUpstreamPage(context, EditProfileView(profile: _profile)),
    );
  }

  void _extend() {
    unawaited(
      openFlvpUpstreamPage(context, ExtendView(profileId: _profile.id)),
    );
  }

  void _preview() {
    unawaited(
      openFlvpUpstreamPage(context, PreviewProfileView(profile: _profile)),
    );
  }

  Future<void> _rename() async {
    await renameProfile(context, ref, _profile);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _profile.url));
    if (mounted) _toast('已复制配置链接');
  }

  Future<void> _showQrCode() {
    return dialogs.showQrCode(
      title: _profile.realLabel,
      data: _profile.url,
      message: '在其它设备扫码导入这份配置',
    );
  }

  Future<void> _export() async {
    await _run(() async {
      final file = await _profile.file;
      if (!await file.exists()) {
        _toast('这份配置还没有本地内容，先同步一次');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _toast('这份配置还没有本地内容，先同步一次');
        return;
      }
      final uri = await picker.saveFile(_profile.exportFileName, bytes);
      if (uri != null && mounted) _toast('已导出「${_profile.exportFileName}」');
    });
  }

  Future<void> _delete() async {
    final action = ref.read(profilesActionProvider.notifier);
    final users = await action.providerUsers(_profile);
    final message = users.isEmpty
        ? '删除「${_profile.realLabel}」后无法恢复。'
        : '「${_profile.realLabel}」正被 '
              '${users.map((item) => item.realLabel).join('、')} 引用，删除后这些引用会失效。';
    final confirmed = await dialogs.showMessage(
      title: '删除配置',
      message: TextSpan(text: message),
      destructive: true,
      confirmText: '删除',
    );
    if (confirmed != true) return;
    await _run(() async {
      await action.deleteProfile(_profile.id);
      if (mounted) _toast('已删除「${_profile.realLabel}」');
    });
  }

  List<_MenuItem> _menuItems() {
    final profile = _profile;
    final isUrl = profile.type == ProfileType.url;
    final isCustom = profile.type == ProfileType.custom;
    return [
      _MenuItem(icon: 'Pencil', label: '编辑', run: _edit),
      if (isCustom)
        _MenuItem(icon: 'Pencil', label: '重命名', run: _rename),
      if (!isCustom)
        _MenuItem(icon: 'SlidersHorizontal', label: '覆写', run: _extend),
      if (isUrl) _MenuItem(icon: 'RefreshCw', label: '同步', run: _sync),
      _MenuItem(icon: 'Eye', label: '运行配置', run: _preview),
      if (isUrl)
        _MenuItem(icon: 'Copy', label: '复制链接', run: _copyLink),
      if (isUrl)
        _MenuItem(icon: 'QrCode', label: '二维码分享', run: _showQrCode),
      _MenuItem(icon: 'Download', label: '导出文件', run: _export),
      _MenuItem(icon: 'Trash2', label: '删除', danger: true, run: _delete),
    ];
  }

  void _openMenu() {
    final theme = FlvpThemeScope.of(context);
    final items = _menuItems();
    _menu = OverlayEntry(
      builder: (context) => FlvpThemeScope(
        colors: theme.colors,
        accent: theme.accent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 4),
              child: _PopMenu(
                items: [
                  for (final item in items)
                    _PopMenuItem(
                      icon: item.icon,
                      label: item.label,
                      danger: item.danger,
                      onTap: () {
                        _closeMenu();
                        unawaited(Future.sync(item.run));
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_menu!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final profile = widget.profile;
    final active = widget.active;
    final mobile = widget.platform == FlvpPlatform.mobile;
    final info = profile.subscriptionInfo;
    final usage = info?.usage;
    final expire = info?.expireDate;
    final daysLeft = _daysLeft(expire);
    final expiring = expire != null && daysLeft <= 30;
    final isUpdating = ref.watch(isUpdatingProvider(profile.updatingKey));
    final groupCount = profile.type == ProfileType.custom
        ? ref.watch(profileGroupsCountProvider(profile.id)).value
        : null;
    final muted = active
        ? colors.onpcontainer.withValues(alpha: 0.75)
        : colors.ink3;
    final metaStyle = flvpText(12, weight: FontWeight.w400, color: muted);
    final label = profile.realLabel;

    return FlvpCard(
      padding: EdgeInsets.all(mobile ? 16 : 20),
      color: active ? colors.pcontainer : colors.surface,
      onTap: () {
        if (active) return;
        ref.read(currentProfileIdProvider.notifier).value = profile.id;
        FlvpStoreScope.read(context).notify('已切换到「$label」');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: FlvpMotion.shape,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? colors.primary : colors.surf2,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  label.isEmpty ? '' : label.substring(0, 1),
                  style: flvpText(
                    16,
                    weight: FontWeight.w600,
                    color: active ? colors.onprimary : colors.ink2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: flvpText(
                                15.5,
                                weight: FontWeight.w600,
                                color: active
                                    ? colors.onpcontainer
                                    : colors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TypeChip(
                            label: _typeLabel(profile.type),
                            active: active,
                          ),
                          if (active) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '使用中',
                                style: flvpText(
                                  11,
                                  weight: FontWeight.w600,
                                  color: colors.onprimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.url.isEmpty
                            ? switch (profile.type) {
                                ProfileType.custom => '自定义配置',
                                _ => '本地文件',
                              }
                            : profile.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          12.5,
                          weight: FontWeight.w400,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(4, -4),
                child: CompositedTransformTarget(
                  link: _link,
                  child: FlvpIconButton(
                    label: '更多操作',
                    active: _menu != null,
                    onPressed: () => _menu != null ? _closeMenu() : _openMenu(),
                    icon: const FlvpIcon('MoreVertical', size: 19),
                  ),
                ),
              ),
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: '已用 ',
                      style: flvpText(
                        12.5,
                        weight: FontWeight.w400,
                        color: active
                            ? colors.onpcontainer.withValues(alpha: 0.85)
                            : colors.ink2,
                      ),
                      children: [
                        TextSpan(
                          text: _sizeText(
                            (info?.upload ?? 0) + (info?.download ?? 0),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(text: ' / ${_sizeText(info?.total ?? 0)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '剩余 ${_sizeText(((info?.total ?? 0) - (info?.upload ?? 0) - (info?.download ?? 0)).clamp(0, 1 << 62))}',
                  style: flvpText(
                    12.5,
                    weight: FontWeight.w600,
                    tabular: true,
                    color: usage > 0.75
                        ? colors.warn
                        : (active ? colors.onpcontainer : colors.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 10,
              child: Center(
                child: isUpdating
                    ? const FlvpWavyProgress()
                    : FlvpProgressBar(
                        value: usage,
                        tone: usage > 0.75
                            ? FlvpProgressTone.warn
                            : FlvpProgressTone.primary,
                      ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              profile.type == ProfileType.url ? '未提供流量 / 到期信息' : '不适用订阅额度',
              style: metaStyle,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (expire != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          FlvpIcon(
                            expiring ? 'TriangleAlert' : 'CalendarClock',
                            size: 13,
                            color: expiring ? colors.warn : muted,
                          ),
                          Text(
                            expiring
                                ? (daysLeft > 0 ? '$daysLeft 天后到期' : '已到期')
                                : '到期 ${_dateText(expire)}',
                            style: expiring
                                ? flvpText(12, color: colors.warn)
                                : metaStyle,
                          ),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        FlvpIcon('RefreshCw', size: 13, color: muted),
                        Text(
                          isUpdating
                              ? '正在更新…'
                              : _stampText(profile.lastUpdateDate),
                          style: metaStyle,
                        ),
                      ],
                    ),
                    if (groupCount != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          FlvpIcon('Network', size: 13, color: muted),
                          Text('$groupCount 个策略组', style: metaStyle),
                        ],
                      ),
                  ],
                ),
              ),
              if (profile.type == ProfileType.url)
                FlvpIconButton(
                  label: '同步配置',
                  onPressed: _busy || isUpdating ? null : _sync,
                  icon: FlvpSpin(
                    active: isUpdating,
                    child: const FlvpIcon('RefreshCw', size: 18),
                  ),
                ),
              if (!active)
                FlvpButton(
                  size: FlvpControlSize.sm,
                  variant: FlvpButtonVariant.tonal,
                  label: '切换',
                  onPressed: () {
                    ref.read(currentProfileIdProvider.notifier).value =
                        profile.id;
                    FlvpStoreScope.read(context).notify('已切换到「$label」');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? colors.onpcontainer.withValues(alpha: 0.12)
            : colors.surf2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: flvpText(
          11,
          weight: FontWeight.w600,
          color: active ? colors.onpcontainer : colors.ink3,
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.run,
    this.danger = false,
  });

  final String icon;
  final String label;
  final FutureOr<void> Function() run;
  final bool danger;
}

class _PopMenu extends StatefulWidget {
  const _PopMenu({required this.items});

  final List<Widget> items;

  @override
  State<_PopMenu> createState() => _PopMenuState();
}

class _PopMenuState extends State<_PopMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: FlvpMotion.pop,
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final pop = CurvedAnimation(parent: _enter, curve: FlvpMotion.easeEntrance);
    return FadeTransition(
      opacity: pop,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(pop),
        alignment: Alignment.topRight,
        child: Container(
          width: 186,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.dialog,
            borderRadius: BorderRadius.circular(16),
            boxShadow: FlvpElevation.float,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: widget.items),
        ),
      ),
    );
  }
}

class _PopMenuItem extends StatelessWidget {
  const _PopMenuItem({
    required this.icon,
    required this.label,
    required this.danger,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpHover(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: FlvpMotion.hover,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: hovered
              ? colors.ink.withValues(alpha: 0.06)
              : const Color(0x00000000),
          child: Row(
            spacing: 12,
            children: [
              FlvpIcon(
                icon,
                size: 17,
                color: danger ? colors.err : colors.ink2,
              ),
              Text(
                label,
                style: flvpText(
                  14,
                  weight: FontWeight.w400,
                  color: danger ? colors.err : colors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
