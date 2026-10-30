import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/store/client_store.dart';
import 'package:flvpcore/ui/widgets/controls.dart';

import 'fake_host.dart';

void main() {
  testWidgets(
    'Windows narrow dashboard switches and manual creation use real store',
    (tester) async {
      tester.view.physicalSize = const Size(720, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('flvp-import-ui-'),
      );
      late ClientController controller;
      late FlvpClientStore store;
      await tester.runAsync(() async {
        controller = ClientController(
          store: SnapshotStore(root!),
          bridge: CoreBridge(FakeHost()),
        );
        store = FlvpClientStore(controller);
        await store.initializeClient();
      });
      addTearDown(() async {
        store.dispose();
        controller.dispose();
        root!.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        FlvpApp(store: store, shell: FlvpShellKind.desktop),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final tun = find.byWidgetPredicate(
        (w) => w is FlvpSwitch && w.label == 'TUN 模式',
      );
      final system = find.byWidgetPredicate(
        (w) => w is FlvpSwitch && w.label == '系统代理',
      );
      expect(tun, findsOneWidget);
      expect(tester.getSize(tun), tester.getSize(system));
      expect(
        tester.getCenter(tun).dx,
        greaterThan(tester.getCenter(system).dx),
      );
      expect(tester.getCenter(tun).dy, tester.getCenter(system).dy);
      await tester.tap(tun);
      await tester.pump();
      expect(store.settings.tunMode, isFalse);
      expect(store.toast?.message, contains('尚未实现'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('nav-subs')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('导入订阅'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('手动创建'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      Finder field(String label) => find.descendant(
        of: find.byWidgetPredicate((w) => w is FlvpField && w.label == label),
        matching: find.byType(TextField),
      );
      await tester.enterText(field('名称'), 'My HTTP');
      await tester.enterText(field('服务器'), '127.0.0.1');
      await tester.enterText(field('端口'), '8080');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('创建'));
        await store.flushSettings();
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.subs.single.name, 'My HTTP');
      expect(controller.library.active?.kind.name, 'manual');
      expect(find.text('本地配置 · 无订阅额度'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
