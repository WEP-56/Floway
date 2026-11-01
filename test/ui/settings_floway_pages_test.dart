import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/settings/access_page.dart';
import 'package:floway/ui/pages/settings/dns_page.dart';
import 'package:floway/ui/pages/settings/font_page.dart';
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

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 1400);
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
              child: Material(child: FlvpModalHost(child: page)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('font page edits the upstream theme font and text scale', (
    tester,
  ) async {
    await pumpPage(tester, const FlvpFontPage(platform: FlvpPlatform.pc));

    expect(find.text('字体与字号'), findsOneWidget);
    expect(find.text('字体族'), findsOneWidget);
    expect(find.text('系统默认'), findsOneWidget);

    // Turning on custom scaling writes ThemeProps.textScale.enable.
    await tester.tap(find.text('自定义字号'));
    await tester.pump();
    expect(container.read(themeSettingProvider).textScale.enable, isTrue);
    expect(find.text('缩放比例'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dns page renders the upstream override entries and adds one', (
    tester,
  ) async {
    await pumpPage(tester, const FlvpDnsPage(platform: FlvpPlatform.pc));

    expect(find.text('DNS'), findsOneWidget);
    // Nothing enabled yet: the empty state offers the add action.
    expect(find.text('还没有启用任何条目'), findsOneWidget);

    await tester.tap(find.byType(FlvpIconButton).last);
    await tester.pump();
    // 'IPv6' is a field label, unambiguous against the section headers.
    expect(find.text('IPv6'), findsWidgets);

    await tester.tap(find.text('IPv6').first);
    await tester.pump();
    expect(
      container.read(patchClashConfigProvider).dnsOverrideKeys.isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('access page keeps the grant entry and saves the app list', (
    tester,
  ) async {
    // vpnSettingProvider 是 autoDispose：测试里保持监听，状态才不会读完即丢。
    container.listen(vpnSettingProvider, (_, _) {});
    container.listen(accessControlStateProvider, (_, _) {});
    await pumpPage(tester, const FlvpAccessPage(platform: FlvpPlatform.pc));

    expect(find.text('应用访问控制'), findsOneWidget);
    expect(find.text('启用访问控制'), findsOneWidget);
    // No app list on the test platform: the grant action must still be there.
    expect(find.text('发起授权'), findsWidgets);
    expect(find.text('还没有读取到应用列表'), findsOneWidget);

    await tester.tap(find.text('启用访问控制'));
    await tester.pump();
    expect(container.read(accessControlStateProvider).enable, isTrue);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(
      container.read(vpnSettingProvider).accessControlProps.enable,
      isTrue,
    );
    // 保存后会弹一条提示，等它的计时器走完再结束用例。
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
