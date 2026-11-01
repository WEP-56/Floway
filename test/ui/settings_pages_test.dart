import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/settings/about_page.dart';
import 'package:floway/ui/pages/settings/hotkey_page.dart';
import 'package:floway/ui/pages/settings/inbound_page.dart';
import 'package:floway/ui/pages/settings/network_page.dart';
import 'package:floway/ui/pages/settings/on_demand_page.dart';
import 'package:floway/ui/pages/settings/string_list_page.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
import 'package:floway/ui/widgets/feedback.dart';
import 'package:floway/ui/widgets/upstream_page.dart';
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

  testWidgets('about page shows version, sources and no contributors', (
    tester,
  ) async {
    await pumpPage(tester, const FlvpAboutPage());

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('Floway'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('构建信息'), findsOneWidget);
    expect(find.textContaining('其它贡献者'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/floway.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hotkey page lists the upstream actions', (tester) async {
    await pumpPage(tester, const FlvpHotKeyPage());

    expect(find.text('快捷键'), findsOneWidget);
    expect(find.text('出站模式'), findsOneWidget);
    expect(find.text('未设置'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inbound page edits the mixed port upstream', (tester) async {
    await pumpPage(
      tester,
      const FlvpInboundPage(platform: FlvpPlatform.pc),
    );

    expect(find.text('入站端口与认证'), findsOneWidget);
    expect(find.text('混合端口'), findsOneWidget);
    expect(find.text('${container.read(patchClashConfigProvider).mixedPort}'),
        findsOneWidget);

    await tester.tap(find.text('混合端口'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('network page exposes the TUN and bypass settings', (
    tester,
  ) async {
    await pumpPage(tester, const FlvpNetworkPage(platform: FlvpPlatform.pc));

    expect(find.text('网络设置'), findsOneWidget);
    expect(find.text('系统代理'), findsOneWidget);
    expect(find.text('排除域名'), findsOneWidget);
    expect(find.text('网络栈'), findsOneWidget);
    expect(find.text('MTU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on demand page explains the SSID list when it is empty', (
    tester,
  ) async {
    await pumpPage(tester, const FlvpOnDemandPage(platform: FlvpPlatform.pc));

    expect(find.text('按需连接'), findsOneWidget);
    expect(find.text('排除的 SSID'), findsOneWidget);
    expect(find.text('还没有排除任何 Wi-Fi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the string list page edits its values', (tester) async {
    var values = <String>['localhost'];
    await pumpPage(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FlvpStringListPage(
          platform: FlvpPlatform.pc,
          title: '排除域名',
          values: values,
          onChanged: (next) => setState(() => values = next),
        ),
      ),
    );

    expect(find.text('localhost'), findsOneWidget);
    await tester.tap(find.byTooltip('删除 localhost'));
    await tester.pump();

    expect(values, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the upstream wrapper hands Floway colors to a page', (
    tester,
  ) async {
    final colors = flvpLightColors(FlvpAccent.indigo);
    ColorScheme? seen;
    await pumpPage(
      tester,
      FlvpUpstreamPage(
        child: Builder(
          builder: (context) {
            seen = Theme.of(context).colorScheme;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen?.primary, colors.primary);
    expect(seen?.surface, colors.surface);
    expect(tester.takeException(), isNull);
  });
}
