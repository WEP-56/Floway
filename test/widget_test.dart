import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floway/ui/app.dart';
import 'package:floway/ui/store/design_store.dart';

void main() {
  for (final shell in FlvpShellKind.values) {
    testWidgets('Floway $shell preview renders', (tester) async {
      tester.view.physicalSize = shell == FlvpShellKind.desktop
          ? const Size(1280, 800)
          : const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = FlvpDesignStore(simulate: false);
      addTearDown(store.dispose);
      await tester.pumpWidget(FlvpApp(store: store, shell: shell));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('已连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
