import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'design/accents.dart';
import 'design/theme_scope.dart';
import 'design/tokens.dart';
import 'nav.dart';
import 'shells/desktop_shell.dart';
import 'shells/mobile_shell.dart';
import 'store/design_store.dart';
import 'store/store_scope.dart';

enum FlvpShellKind { desktop, mobile }

/// The replicated UI: the design's `AppProvider` + one of its two shells.
///
/// Desktop hosts get the window shell, touch platforms the phone shell;
/// [shell] overrides that (tests, previews). [preview] renders the design's
/// device chrome (window frame / fake status bar) for 1:1 comparison.
class FlvpApp extends StatefulWidget {
  const FlvpApp({
    super.key,
    this.store,
    this.shell,
    this.preview = false,
    this.initialPage = FlvpPageKey.dashboard,
  });

  final FlvpDesignStore? store;
  final FlvpShellKind? shell;
  final bool preview;
  final FlvpPageKey initialPage;

  @override
  State<FlvpApp> createState() => _FlvpAppState();
}

class _FlvpAppState extends State<FlvpApp> with WidgetsBindingObserver {
  late final FlvpDesignStore _store = widget.store ?? FlvpDesignStore();
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
      final shell =
          widget.shell ??
          (!kIsWeb && (Platform.isAndroid || Platform.isIOS)
              ? FlvpShellKind.mobile
              : FlvpShellKind.desktop);
      final windows = !kIsWeb && Platform.isWindows;
      return MaterialApp(
        title: 'Floway',
        debugShowCheckedModeBanner: false,
        color: colors.frame,
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          // The design's font stack: Segoe UI Variable on Windows, the
          // platform sans elsewhere, with CJK fallbacks.
          fontFamily: windows ? 'Segoe UI Variable Text' : null,
          fontFamilyFallback: windows
              ? const ['Segoe UI', 'Microsoft YaHei UI', 'Microsoft YaHei']
              : const ['Noto Sans SC', 'Noto Sans CJK SC', 'Source Han Sans SC'],
          scaffoldBackgroundColor: colors.frame,
          splashFactory: NoSplash.splashFactory,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: colors.primary,
            selectionColor: colors.primary.withValues(alpha: 0.25),
            selectionHandleColor: colors.primary,
          ),
          tooltipTheme: TooltipThemeData(
            waitDuration: const Duration(milliseconds: 600),
            textStyle: flvpText(12, weight: FontWeight.w400, color: colors.canvas),
            decoration: BoxDecoration(
              color: colors.ink,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        home: FlvpThemeScope(
          colors: colors,
          accent: accent,
          child: FlvpStoreScope(
            store: _store,
            child: DefaultTextStyle(
              style: flvpText(14, weight: FontWeight.w400, color: colors.ink),
              child: Material(
                color: colors.frame,
                child: shell == FlvpShellKind.desktop
                    ? FlvpDesktopShell(
                        framed: widget.preview,
                        initialPage: widget.initialPage,
                      )
                    : FlvpMobileShell(
                        mock: widget.preview,
                        initialPage: widget.initialPage,
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
