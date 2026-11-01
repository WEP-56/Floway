import 'package:floway/models/models.dart';
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import 'controls.dart';
import 'ripple.dart';

/// 规则行：Floway 的规则卡片（动作徽章 + 内容 + 目标 + 可选编辑/删除）。
///
/// 附加规则、配置覆写两处共用；选择模式由 `onSelect` 打开（左侧圆形勾选）。
class FlvpRuleRow extends StatelessWidget {
  const FlvpRuleRow({
    super.key,
    required this.rule,
    this.indexWidget,
    this.selected,
    this.onSelect,
    this.onEdit,
    this.onDelete,
    this.onTap,
  });

  final Rule rule;

  /// 拖拽手柄（可排序列表传入）。
  final Widget? indexWidget;

  final bool? selected;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final content = rule.realContent ?? '';
    final target = rule.realTarget ?? '';
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: colors.ink,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap ?? onSelect ?? onEdit,
          child: AnimatedContainer(
            duration: FlvpMotion.hover,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: hovered ? colors.surf2 : colors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: FlvpElevation.card,
            ),
            child: Row(
              children: [
                ?indexWidget,
                if (onSelect != null) ...[
                  _SelectBox(selected: selected == true, onTap: onSelect!),
                  const SizedBox(width: 10),
                ],
                _TypeBadge(label: rule.ruleAction.value),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        content.isEmpty ? '（匹配全部）' : content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: flvpText(
                          13.5,
                          weight: FontWeight.w500,
                          color: colors.ink,
                          mono: true,
                        ),
                      ),
                      Row(
                        spacing: 4,
                        children: [
                          FlvpIcon('ChevronRight', size: 12, color: colors.ink3),
                          Flexible(
                            child: Text(
                              target.isEmpty ? '—' : target,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: flvpText(
                                12,
                                weight: FontWeight.w400,
                                color: colors.ink2,
                              ),
                            ),
                          ),
                          if (rule.noResolve)
                            _Mini(label: 'no-resolve', color: colors.warn),
                          if (rule.src) _Mini(label: 'src', color: colors.warn),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onEdit != null || onDelete != null) ...[
                  const SizedBox(width: 6),
                  if (onEdit != null)
                    FlvpIconButton(
                      label: '编辑',
                      dimension: 34,
                      onPressed: onEdit,
                      icon: const FlvpIcon('Pencil', size: 16),
                    ),
                  if (onDelete != null)
                    FlvpIconButton(
                      label: '删除',
                      dimension: 34,
                      onPressed: onDelete,
                      icon: const FlvpIcon('Trash2', size: 16),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
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
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(minWidth: 56),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.pcontainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: flvpText(11, weight: FontWeight.w600, color: colors.onpcontainer),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: flvpText(10.5, weight: FontWeight.w600, color: color),
      ),
    );
  }
}
