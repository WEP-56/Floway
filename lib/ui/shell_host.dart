import 'dart:io';

import 'package:floway/providers/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'backend.dart';
import 'design/accents.dart';
import 'design/theme_scope.dart';
import 'design/tokens.dart';
import 'nav.dart';
import 'shells/desktop_shell.dart';
import 'shells/mobile_shell.dart';
import 'store/design_store.dart';
import 'store/store_scope.dart';

/// 把 Floway 前端资产装到上游运行基础上：上游 MaterialApp 提供路由、
/// 本地化与各 Manager，这里只提供 Floway 的主题作用域与两端壳。
///
/// 主题不再由 Floway 自己的设置决定：深浅跟随上游 `themeMode`/系统亮度，
/// 色相取自上游主题色（动态取色或自定义配色），纯黑开关同样透传。
class FlvpShellHost extends ConsumerStatefulWidget {
  const FlvpShellHost({
    super.key,
    this.store,
    this.initialPage = FlvpPageKey.dashboard,
  });

  final FlvpDesignStore? store;
  final FlvpPageKey initialPage;

  @override
  ConsumerState<FlvpShellHost> createState() => _FlvpShellHostState();
}

class _FlvpShellHostState extends ConsumerState<FlvpShellHost>
    with WidgetsBindingObserver {
  late final FlvpDesignStore _store =
      widget.store ?? FlvpDesignStore(simulate: false);
  final Map<(double, bool, bool), FlvpColors> _palettes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.setPlatformBrightness(PlatformDispatcher.instance.platformBrightness);
  }

  @override
  void didChangePlatformBrightness() {
    _store.setPlatformBrightness(PlatformDispatcher.instance.platformBrightness);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  FlvpColors _colors(double hue, {required bool dark, required bool pureBlack}) =>
      _palettes.putIfAbsent(
        (hue, dark, pureBlack),
        () => dark
            ? flvpDarkColorsOfHue(hue, pureBlack: pureBlack)
            : flvpLightColorsOfHue(hue),
      );

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(currentBrightnessProvider) == Brightness.dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ref.watch(genColorSchemeProvider(brightness));
    final pureBlack = ref.watch(
      themeSettingProvider.select((state) => state.pureBlack),
    );
    final hue = HSVColor.fromColor(scheme.primary).hue;
    final colors = _colors(hue, dark: dark, pureBlack: pureBlack);
    final mobile = !kIsWeb && Platform.isAndroid;
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => FlvpThemeScope(
        colors: colors,
        accent: FlvpAccent.indigo,
        child: FlvpStoreScope(
          store: _store,
          child: FlvpBackendBinder(
            store: _store,
            child: DefaultTextStyle(
              style: flvpText(14, weight: FontWeight.w400, color: colors.ink),
              child: Material(
                color: colors.frame,
                child: mobile
                    ? FlvpMobileShell(initialPage: widget.initialPage)
                    : FlvpDesktopShell(initialPage: widget.initialPage),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
