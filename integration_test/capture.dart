import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/design/accents.dart';
import 'package:flvpcore/ui/nav.dart';
import 'package:flvpcore/ui/store/design_store.dart';
import 'package:flvpcore/ui/store/models.dart';

/// Renders the replicated shell at the design's reference size (the preview's
/// desktop window is 1025x720 side by side with the 375x780 phone screen) with
/// the preview chrome and writes a 1x PNG, so it can be compared against the
/// React preview crops.
Future<void> captureShell(
  WidgetTester tester, {
  required FlvpShellKind shell,
  required String file,
  FlvpPageKey page = FlvpPageKey.dashboard,
  bool dark = false,
  FlvpAccent accent = FlvpAccent.indigo,
}) async {
  final size = shell == FlvpShellKind.desktop
      ? const Size(1025, 720)
      : const Size(375, 780);
  final store = FlvpDesignStore(
    settings: AppSettings(
      theme: dark ? FlvpThemeMode.dark : FlvpThemeMode.light,
      accent: accent,
    ),
  );
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      // The test window may be smaller than the reference size; lay the shell
      // out at full size regardless and capture its layer.
      child: OverflowBox(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: RepaintBoundary(
          key: key,
          child: FlvpApp(
            store: store,
            shell: shell,
            preview: true,
            initialPage: page,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 500));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final target = File(file);
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  await tester.pumpWidget(const SizedBox());
  store.dispose();
}
