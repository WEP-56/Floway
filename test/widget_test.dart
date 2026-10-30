import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/store/design_store.dart';
import 'package:flvpcore/ui/widgets/hero.dart';

/// Smoke test of the replicated design shell: every page renders on both
/// shells, the import dialog / sheet opens, the power button toggles state.
/// Repeating animations (breathing dot, blob rotation, traffic simulation)
/// mean `pumpAndSettle` never settles, so frames are pumped explicitly.
void main() {
  for (final (shell, size) in [
    (FlvpShellKind.desktop, const Size(1280, 800)),
    (FlvpShellKind.mobile, const Size(360, 800)),
  ]) {
    testWidgets('Replicated $shell shell renders every page at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FlvpDesignStore();
      var disposed = false;
      addTearDown(() {
        if (!disposed) store.dispose();
      });

      await tester.pumpWidget(FlvpApp(store: store, shell: shell));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已连接'), findsOneWidget);
      if (shell == FlvpShellKind.desktop) {
        expect(find.text('运行中'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      for (final page in ['nodes', 'subs', 'settings', 'dashboard']) {
        await tester.tap(find.byKey(ValueKey('nav-$page')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        if (page == 'subs') {
          expect(find.text('FLVP 高级订阅'), findsOneWidget);
          await tester.tap(find.text('导入订阅'));
          // Entrance animations start on the frame that mounts the modal.
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('支持 Clash、Sing-box 与 V2Ray 订阅链接'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('支持 Clash、Sing-box 与 V2Ray 订阅链接'), findsNothing);
        }
        if (page == 'settings') {
          await tester.tap(find.text('主题'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('外观模式与动态配色'), findsOneWidget);
          await tester.tap(find.text('青碧'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(store.settings.accent.name, 'teal');
          await tester.tapAt(const Offset(4, 4)); // scrim
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('外观模式与动态配色'), findsNothing);
        }
      }

      await tester.tap(find.byType(FlvpPowerButton));
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.running, isFalse);
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text('代理已停止'), findsOneWidget);

      if (shell == FlvpShellKind.desktop) {
        await tester.tap(find.byKey(const ValueKey('nav-theme')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(store.resolvedDark, isTrue);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
      disposed = true;
    });
  }
}
