import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/add_profile_modal.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
import 'package:floway/ui/widgets/controls.dart';
import 'package:floway/ui/widgets/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    globalState.container = container;
    addTearDown(container.dispose);
  });

  Future<void> pumpModal(
    WidgetTester tester, {
    FlvpPlatform platform = FlvpPlatform.pc,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              child: Material(
                child: FlvpAddProfileModal(
                  platform: platform,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Let the dialog / sheet entrance finish so taps land on screen.
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('offers the four upstream ways to add a profile', (tester) async {
    await pumpModal(tester);

    for (final label in ['链接', '文件', '二维码', '自定义']) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(find.text('添加配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the link import disabled until a link is valid', (
    tester,
  ) async {
    await pumpModal(tester);

    final import = find.widgetWithText(FlvpButton, '导入');
    expect(import, findsOneWidget);
    expect(tester.widget<FlvpButton>(import).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'https://example.com/sub');
    await tester.pump();

    expect(tester.widget<FlvpButton>(import).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains the custom workspace instead of a manual form', (
    tester,
  ) async {
    await pumpModal(tester, platform: FlvpPlatform.mobile);

    await tester.tap(find.text('自定义'));
    await tester.pump();

    expect(find.textContaining('自定义配置不使用订阅链接'), findsOneWidget);
    expect(find.text('创建并打开'), findsOneWidget);
    expect(find.text('手动创建'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
