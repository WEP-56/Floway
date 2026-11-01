import 'package:floway/manager/theme_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_scope.dart';
import 'page_scaffold.dart';

/// 给尚未改写成 Floway 版式的上游页面套一层 Floway 配色。
///
/// 保留上游 `ThemeData` 的形状、排版与扩展（`withAppShapes` 等），只把
/// `ColorScheme` 换成 Floway 的 token，让二级页与一级页颜色一致。
class FlvpUpstreamPage extends ConsumerWidget {
  const FlvpUpstreamPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = FlvpThemeScope.colorsOf(context);
    final brightness = colors.dark ? Brightness.dark : Brightness.light;
    final base = watchAppTheme(ref, brightness);
    final scheme = base.colorScheme.copyWith(
      primary: colors.primary,
      onPrimary: colors.onprimary,
      primaryContainer: colors.pcontainer,
      onPrimaryContainer: colors.onpcontainer,
      secondary: colors.primary,
      onSecondary: colors.onprimary,
      secondaryContainer: colors.scontainer,
      onSecondaryContainer: colors.onscontainer,
      surface: colors.surface,
      onSurface: colors.ink,
      surfaceTint: Colors.transparent,
      onSurfaceVariant: colors.ink2,
      surfaceDim: colors.surf3,
      surfaceBright: colors.surface,
      surfaceContainerLowest: colors.canvas,
      surfaceContainerLow: colors.surf2,
      surfaceContainer: colors.surf2,
      surfaceContainerHigh: colors.surf3,
      surfaceContainerHighest: colors.surf3,
      outline: colors.hair,
      outlineVariant: colors.hair,
      error: colors.err,
      onError: colors.surface,
      errorContainer: colors.err.withValues(alpha: 0.14),
      onErrorContainer: colors.err,
      inverseSurface: colors.ink,
      onInverseSurface: colors.canvas,
      inversePrimary: colors.invprimary,
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: colors.canvas,
        canvasColor: colors.canvas,
        dividerColor: colors.hair,
      ),
      child: child,
    );
  }
}

/// 打开一个上游页面，并让它使用 Floway 配色。
Future<void> openFlvpUpstreamPage(BuildContext context, Widget page) async {
  await pushFlvpPage<void>(context, FlvpUpstreamPage(child: page));
}
