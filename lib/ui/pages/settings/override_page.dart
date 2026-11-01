import 'package:floway/common/common.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/features/form/custom_issue.dart';
import 'package:floway/models/models.dart';
import 'package:floway/views/config/override.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../design/theme_scope.dart';
import '../../design/tokens.dart';
import '../../icons/flvp_icon.dart';
import '../../widgets/controls.dart';
import '../../widgets/feedback.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/surfaces.dart';

/// 上游覆写规格（[OverrideSpec]）的 Floway 版渲染器。
///
/// 数据与生效方式完全沿用上游：这里只把「按分组列出启用项、逐项编辑、
/// 增删条目」的呈现换成 Floway 的卡片/行样式。DNS 与配置覆写共用同一实现，
/// 字段类型按上游 [OverrideField] 的实际子类分派，不复制任何校验规则。
class FlvpOverridePage<K extends OverrideKey, M>
    extends ConsumerWidget {
  const FlvpOverridePage({
    super.key,
    required this.spec,
    required this.platform,
    this.subtitle,
  });

  final OverrideSpec<K, M> spec;
  final FlvpPlatform platform;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final appLocalizations = currentAppLocalizations;
    final target = spec.target;
    final keys = ref.watch(target.select((state) => state.keys.toList()));
    final enabled = [for (final key in spec.values) if (keys.contains(key)) key];
    final remaining = [for (final key in spec.values) if (!keys.contains(key)) key];
    final issues = target.issues;
    final issueList = issues == null ? const <CustomIssue>[] : ref.watch(issues);

    return FlvpPageScaffold(
      title: spec.title(appLocalizations),
      subtitle: subtitle ?? '${enabled.length} 项已启用',
      actions: [
        if (remaining.isNotEmpty)
          FlvpIconButton(
            label: '添加条目',
            dimension: 40,
            onPressed: () => _showAdd(context, ref, remaining, colors),
            icon: const FlvpIcon('Plus', size: 20),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (issueList.isNotEmpty) _IssuesBanner(issues: issueList),
          if (enabled.isEmpty)
            _empty(colors)
          else ...[
            for (final (section, sectionKeys) in spec.sectionsOf(
              appLocalizations,
              enabled,
            ))
              FlvpSettingsSection(
                title: section,
                children: [
                  for (final key in sectionKeys)
                    _fieldRow(context, ref, key, colors),
                ],
              ),
            if (remaining.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FlvpButton(
                  variant: FlvpButtonVariant.tonal,
                  label: '添加条目（还有 ${remaining.length} 项）',
                  icon: const FlvpIcon('Plus', size: 16),
                  onPressed: () => _showAdd(context, ref, remaining, colors),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _empty(FlvpColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        spacing: 10,
        children: [
          FlvpIcon('SlidersHorizontal', size: 26, color: colors.ink3),
          Text('还没有启用任何条目', style: flvpText(13.5, color: colors.ink3)),
          Text(
            '从右上角添加，未添加的项沿用配置本身的值',
            style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
          ),
        ],
      ),
    );
  }

  void _showAdd(
    BuildContext context,
    WidgetRef ref,
    List<K> remaining,
    FlvpColors colors,
  ) {
    final appLocalizations = currentAppLocalizations;
    final host = FlvpModalHost.of(context);
    final sections = <(String, List<K>)>[];
    for (final key in remaining) {
      final title = spec.sectionOf(key, appLocalizations);
      final index = sections.indexWhere((item) => item.$1 == title);
      if (index == -1) {
        sections.add((title, [key]));
      } else {
        sections[index].$2.add(key);
      }
    }
    host.show(
      (context) => FlvpModal(
        platform: platform,
        title: spec.target.addEntry(appLocalizations),
        subtitle: '选中的项会被写入配置',
        onClose: host.close,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420, maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (section, keys) in sections) ...[
                FlvpSectionLabel(title: section),
                for (final key in keys)
                  FlvpRow(
                    title: spec.label(key, appLocalizations),
                    subtitle: spec.description(key)?.call(appLocalizations),
                    onTap: () {
                      spec.target.update(
                        ref,
                        (state) => (
                          model: spec.fieldOf(key).reset(state.model, spec.defaults),
                          keys: {...state.keys, key},
                        ),
                      );
                      host.close();
                    },
                    trailing: FlvpIcon('Plus', size: 16, color: colors.ink3),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(
    BuildContext context,
    WidgetRef ref,
    K key,
    FlvpColors colors,
  ) {
    final appLocalizations = currentAppLocalizations;
    final title = spec.label(key, appLocalizations);
    final description = spec.description(key)?.call(appLocalizations);
    final field = spec.fieldOf(key);
    final model = spec.target;

    void remove() {
      spec.target.update(
        ref,
        (state) => spec.withoutKeys(state, {key}),
      );
    }

    final deleteButton = FlvpIconButton(
      label: '移除 $title',
      dimension: 32,
      onPressed: remove,
      icon: FlvpIcon('X', size: 14, color: colors.ink3),
    );

    Widget row(Widget trailing) => FlvpRow(
      icon: const FlvpIcon('SlidersHorizontal', size: 18),
      title: title,
      subtitle: description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [trailing, deleteButton],
      ),
    );

    switch (field) {
      case ToggleOverrideField<M>():
        final value = ref.watch(model.selectModel(field.select));
        return row(
          FlvpSwitch(
            value: value,
            label: title,
            onChanged: (next) => model.modelWriter(field.update)(ref, next),
          ),
        );
      case OptionsOverrideField<M, Object>():
        final value = ref.watch(model.selectModel(field.select));
        final current = field.labelOf(value);
        return row(
          GestureDetector(
            onTap: () async {
              final next = await showFlvpOptionsPrompt<Object>(
                context: context,
                platform: platform,
                title: title,
                value: value,
                options: [
                  for (final option in field.options)
                    FlvpRadioOption(option, field.labelOf(option)),
                ],
              );
              if (next == null) return;
              model.modelWriter(field.update)(ref, next);
            },
            child: _valueText(current, colors),
          ),
        );
      case NumberOverrideField<M>():
        final value = ref.watch(model.selectModel(field.select));
        return row(
          GestureDetector(
            onTap: () async {
              final next = await showFlvpNumberPrompt(
                context: context,
                platform: platform,
                title: title,
                value: value,
                min: field.min,
                max: field.max,
              );
              if (next == null || next == value) return;
              model.modelWriter(field.update)(ref, next);
            },
            child: _valueText('$value', colors),
          ),
        );
      case TextOverrideField<M>():
        final value = ref.watch(model.selectModel(field.select));
        return row(
          GestureDetector(
            onTap: () async {
              final next = await showFlvpTextPrompt(
                context: context,
                platform: platform,
                title: title,
                subtitle: description,
                value: value,
                validator: (input) =>
                    field.validator?.call(input, currentAppLocalizations),
              );
              if (next == null || next.trim() == value) return;
              model.modelWriter(field.update)(ref, next.trim());
            },
            child: _valueText(value.isEmpty ? '未设置' : value, colors),
          ),
        );
      case ListOverrideField<M>():
        final value = ref.watch(model.selectModel(field.select));
        return FlvpRow(
          icon: const FlvpIcon('Route', size: 18),
          title: title,
          subtitle: value.isEmpty ? '（空）' : '${value.length} 项',
          onTap: () => _editList(context, ref, field, title, value, colors),
          trailing: deleteButton,
        );
      default:
        return row(const SizedBox.shrink());
    }
  }

  Widget _valueText(String text, FlvpColors colors) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: flvpText(13, weight: FontWeight.w400, color: colors.ink2),
            ),
          ),
          FlvpIcon('ChevronRight', size: 14, color: colors.ink3),
        ],
      ),
    );
  }

  Future<void> _editList(
    BuildContext context,
    WidgetRef ref,
    ListOverrideField<M> field,
    String title,
    List<String> initial,
    FlvpColors colors,
  ) async {
    final host = FlvpModalHost.of(context);
    final model = spec.target;
    var items = List<String>.from(initial);

    void write(List<String> next) {
      items = next;
      model.modelWriter(field.update)(ref, next);
    }

    host.show(
      (context) => StatefulBuilder(
        builder: (context, setModal) => FlvpModal(
          platform: platform,
          title: title,
          subtitle: '每行一项',
          onClose: host.close,
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              '还没有条目',
                              style: flvpText(13, color: colors.ink3),
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final item in items)
                              FlvpRow(
                                title: item,
                                onTap: () async {
                                  final next = await showFlvpTextPrompt(
                                    context: context,
                                    platform: platform,
                                    title: title,
                                    value: item,
                                    validator: (input) {
                                      if (input.isEmpty) return '不能为空';
                                      return field.itemValidator
                                          ?.call(input, currentAppLocalizations);
                                    },
                                  );
                                  if (next == null) return;
                                  final result = List<String>.from(items);
                                  final index = result.indexOf(item);
                                  if (index >= 0) result[index] = next.trim();
                                  write(result);
                                  setModal(() {});
                                },
                                trailing: FlvpIconButton(
                                  label: '删除',
                                  dimension: 30,
                                  onPressed: () {
                                    write([
                                      ...items.where((it) => it != item),
                                    ]);
                                    setModal(() {});
                                  },
                                  icon: FlvpIcon('X', size: 13, color: colors.ink3),
                                ),
                              ),
                          ],
                        ),
                ),
                FlvpButton(
                  variant: FlvpButtonVariant.tonal,
                  label: '添加一项',
                  icon: const FlvpIcon('Plus', size: 16),
                  onPressed: () async {
                    final next = await showFlvpTextPrompt(
                      context: context,
                      platform: platform,
                      title: title,
                      validator: (input) {
                        if (input.isEmpty) return '不能为空';
                        return field.itemValidator
                            ?.call(input, currentAppLocalizations);
                      },
                    );
                    if (next == null) return;
                    write([...items, next.trim()]);
                    setModal(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IssuesBanner extends StatelessWidget {
  const _IssuesBanner({required this.issues});

  final List<CustomIssue> issues;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
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
                issues.getMessage(context),
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
    );
  }
}
