import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/shells/mobile_shell.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('the phone shell keeps four dock entries above the content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 733);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(360, 733);
    addTearDown(container.dispose);
    final store = FlvpDesignStore(simulate: false);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: FlvpThemeScope(
            colors: flvpLightColors(FlvpAccent.indigo),
            accent: FlvpAccent.indigo,
            child: FlvpStoreScope(
              store: store,
              child: const FlvpMobileShell(mock: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final label in ['仪表盘', '代理', '配置', '设置']) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }

    // 悬浮 dock：左右各留 12，底部留白，内容从它下面穿过。
    final dock = find.byKey(const ValueKey('nav-dashboard'));
    expect(dock, findsOneWidget);
    final rect = tester.getRect(dock);
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.bottom, lessThanOrEqualTo(733 - 10));

    // 每个槽位里的图标与文字都要在槽位中线上，四项等宽。
    const keys = ['dashboard', 'proxies', 'profiles', 'settings'];
    final centers = <double>[];
    for (final key in keys) {
      final slot = tester.getRect(find.byKey(ValueKey('nav-$key')));
      final label = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('nav-$key')),
          matching: find.byType(Text),
        ),
      );
      expect(
        (label.center.dx - slot.center.dx).abs(),
        lessThan(1.5),
        reason: 'label of $key is not centred in its slot',
      );
      centers.add(slot.center.dx);
    }
    final gaps = [
      for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
    ];
    for (final gap in gaps) {
      expect(gap, closeTo(gaps.first, 0.5), reason: 'dock items are not even');
    }
    expect(tester.takeException(), isNull);
  });
}
