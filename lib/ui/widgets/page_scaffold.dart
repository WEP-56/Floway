import 'dart:async';
import 'dart:math' as math;

import 'package:floway/ui/navigator.dart';
import 'package:material_ui/material_ui.dart';

import '../design/accents.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../store/design_store.dart';
import '../store/store_scope.dart';
import 'controls.dart';
import 'feedback.dart';

/// 二级页的上下文：主题、store 与弹层宿主。
///
/// 二级页是根 Navigator 上的整页路由，而 `FlvpThemeScope` / `FlvpStoreScope`
/// 装在壳里（`MaterialApp.home` 之下），路由不在它们的子树里。所以打开二级页
/// 时要把这两个作用域重新挂一遍，并给它自己的 `FlvpModalHost`。
class FlvpPageScope extends StatelessWidget {
  const FlvpPageScope({
    super.key,
    required this.colors,
    required this.accent,
    required this.store,
    required this.child,
  });

  final FlvpColors colors;
  final FlvpAccent accent;
  final FlvpDesignStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => FlvpThemeScope(
    colors: colors,
    accent: accent,
    child: FlvpStoreScope(
      store: store,
      child: Material(
        color: colors.canvas,
        child: FlvpModalHost(child: child),
      ),
    ),
  );
}

/// 打开一个 Floway 二级页，并把主题/store/弹层宿主带过去。
Future<T?> pushFlvpPage<T>(BuildContext context, Widget page) {
  final theme = FlvpThemeScope.of(context);
  final store = FlvpStoreScope.read(context);
  return BaseNavigator.push<T>(
    context,
    FlvpPageScope(
      colors: theme.colors,
      accent: theme.accent,
      store: store,
      child: page,
    ),
  );
}

/// 设置/配置二级页的外壳：Floway 标题栏（返回 + 标题 + 操作）与可滚动内容。
///
/// 二级页是整页路由，所以自带背景色与安全区，不依赖壳里的滚动视图。
class FlvpPageScaffold extends StatelessWidget {
  const FlvpPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.scrollable = true,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// 需要页面自带列表/滚动（例如可拖拽排序的列表）时置 false，正文直接
  /// 放进 Expanded，不再套一层 SingleChildScrollView。
  final bool scrollable;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: colors.canvas,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  spacing: 8,
                  children: [
                    FlvpIconButton(
                      label: '返回',
                      dimension: 40,
                      onPressed: () => Navigator.maybePop(context),
                      icon: Transform.rotate(
                        angle: math.pi,
                        child: const FlvpIcon('ChevronRight', size: 20),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: flvpText(
                              20,
                              letterSpacing: -0.4,
                              color: colors.ink,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: flvpText(
                                12,
                                weight: FontWeight.w400,
                                color: colors.ink3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
            Expanded(
              child: scrollable
                  ? ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          24 + padding.bottom,
                        ),
                        child: child,
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.only(bottom: padding.bottom),
                      child: child,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的单行文本输入，返回去掉首尾空白的文本；取消或关闭返回 null。
Future<String?> showFlvpTextPrompt({
  required BuildContext context,
  required FlvpPlatform platform,
  required String title,
  String? subtitle,
  String value = '',
  String? placeholder,
  String confirmLabel = '确定',
  String? Function(String value)? validator,
}) {
  final completer = Completer<String?>();
  final host = FlvpModalHost.of(context);
  var text = value;
  String? error;

  void close([String? result]) {
    host.close();
    if (!completer.isCompleted) completer.complete(result);
  }

  host.show(
    (context) => StatefulBuilder(
      builder: (context, setState) => FlvpModal(
        platform: platform,
        title: title,
        subtitle: subtitle,
        onClose: () => close(),
        footer: [
          FlvpButton(
            variant: FlvpButtonVariant.text,
            label: '取消',
            onPressed: () => close(),
          ),
          FlvpButton(
            label: confirmLabel,
            onPressed: () {
              final next = text.trim();
              final message = validator?.call(next);
              if (message != null) {
                setState(() => error = message);
                return;
              }
              close(next);
            },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            FlvpField(
              label: title,
              value: text,
              placeholder: placeholder,
              mono: true,
              onChanged: (next) => setState(() {
                text = next;
                error = null;
              }),
            ),
            if (error != null)
              Text(
                error!,
                style: flvpText(
                  12,
                  weight: FontWeight.w400,
                  color: FlvpThemeScope.colorsOf(context).warn,
                ),
              ),
          ],
        ),
      ),
    ),
  );
  return completer.future;
}

/// 数字输入弹层：范围校验后返回整数；取消返回 null。
Future<int?> showFlvpNumberPrompt({
  required BuildContext context,
  required FlvpPlatform platform,
  required String title,
  String? subtitle,
  required int value,
  int min = 0,
  int max = 0xFFFFFFFF,
  String? suffix,
}) async {
  final text = await showFlvpTextPrompt(
    context: context,
    platform: platform,
    title: title,
    subtitle: subtitle,
    value: '$value',
    placeholder: suffix == null ? null : '$min – $max $suffix',
    validator: (input) {
      final number = int.tryParse(input);
      if (number == null) return '请输入数字';
      if (number < min || number > max) return '取值范围 $min – $max';
      return null;
    },
  );
  if (text == null) return null;
  return int.tryParse(text);
}

/// 单选弹层：选中即写回并关闭。
Future<T?> showFlvpOptionsPrompt<T>({  required BuildContext context,
  required FlvpPlatform platform,
  required String title,
  String? subtitle,
  required T value,
  required List<FlvpRadioOption<T>> options,
}) {
  final completer = Completer<T?>();
  final host = FlvpModalHost.of(context);

  void close([T? result]) {
    host.close();
    if (!completer.isCompleted) completer.complete(result);
  }

  host.show(
    (context) => FlvpModal(
      platform: platform,
      title: title,
      subtitle: subtitle,
      onClose: () => close(),
      child: FlvpRadioList<T>(
        value: value,
        options: options,
        onChanged: (next) => close(next),
      ),
    ),
  );
  return completer.future;
}

/// 确认弹层：确认返回 true，取消 / 关闭返回 null。
Future<bool?> showFlvpConfirm({
  required BuildContext context,
  required FlvpPlatform platform,
  required String title,
  String? message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = false,
}) {
  final completer = Completer<bool?>();
  final host = FlvpModalHost.of(context);
  final colors = FlvpThemeScope.colorsOf(context);

  void close([bool? result]) {
    host.close();
    if (!completer.isCompleted) completer.complete(result);
  }

  host.show(
    (context) => FlvpModal(
      platform: platform,
      title: title,
      onClose: () => close(),
      footer: [
        FlvpButton(
          variant: FlvpButtonVariant.text,
          label: cancelLabel,
          onPressed: () => close(),
        ),
        FlvpButton(
          variant: danger ? FlvpButtonVariant.danger : FlvpButtonVariant.filled,
          label: confirmLabel,
          onPressed: () => close(true),
        ),
      ],
      child: message == null
          ? const SizedBox.shrink()
          : Text(
              message,
              style: flvpText(
                13.5,
                weight: FontWeight.w400,
                height: 1.6,
                color: colors.ink2,
              ),
            ),
    ),
  );
  return completer.future;
}
