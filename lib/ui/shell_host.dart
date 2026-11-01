import 'dart:io';

import 'package:flutter/foundation.dart';
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
class FlvpShellHost extends StatefulWidget {
  const FlvpShellHost({
    super.key,
    this.store,
    this.initialPage = FlvpPageKey.dashboard,
  });

  final FlvpDesignStore? store;
  final FlvpPageKey initialPage;

  @override
  State<FlvpShellHost> createState() => _FlvpShellHostState();
}

class _FlvpShellHostState extends State<FlvpShellHost> with WidgetsBindingObserver {
  late final FlvpDesignStore _store =
      widget.store ?? FlvpDesignStore(simulate: false);
  final Map<(FlvpAccent, bool), FlvpColors> _palettes = {};

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

  FlvpColors _colors(FlvpAccent accent, bool dark) => _palettes.putIfAbsent(
    (accent, dark),
    () => dark ? flvpDarkColors(accent) : flvpLightColors(accent),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final dark = _store.resolvedDark;
      final accent = _store.accent;
      final colors = _colors(accent, dark);
      final mobile = !kIsWeb && Platform.isAndroid;
      return FlvpThemeScope(
        colors: colors,
        accent: accent,
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
      );
    },
  );
}