import 'package:floway/enum/enum.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/nav.dart';
import 'package:floway/ui/pages/settings_page.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
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

  Future<void> pumpSettings(
    WidgetTester tester, {
    FlvpPlatform platform = FlvpPlatform.pc,
    double width = 1100,
    ValueChanged<FlvpPageKey>? onNavigate,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
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
                child: FlvpModalHost(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: FlvpSettingsPage(
                      platform: platform,
                      onNavigate: onNavigate,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the upstream settings groups', (tester) async {
    await pumpSettings(tester);

    for (final label in [
      '外观与交互',
      '启动与后台',
      '代理与网络',
      '配置与规则',
      '资源管理',
      '平台功能',
      '数据与备份',
      '应用与信息',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('跟随系统'), findsWidgets);
    expect(find.text('入站端口与认证'), findsOneWidget);
    expect(find.text('网络设置'), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a toggle row writes the upstream patch config', (tester) async {
    await pumpSettings(tester);

    expect(
      container.read(patchClashConfigProvider).findProcessMode,
      FindProcessMode.off,
    );
    await tester.tap(find.text('按进程查找'));
    await tester.pump();

    expect(
      container.read(patchClashConfigProvider).findProcessMode,
      FindProcessMode.always,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the language sheet writes the upstream locale', (tester) async {
    await pumpSettings(tester);

    expect(container.read(appSettingProvider).locale, isNull);
    await tester.tap(find.text('语言'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();

    expect(container.read(appSettingProvider).locale, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shows the Android-only entries', (tester) async {
    await pumpSettings(tester, platform: FlvpPlatform.mobile, width: 420);

    expect(find.text('应用访问控制'), findsOneWidget);
    expect(find.text('快捷键'), findsNothing);
    expect(find.text('开机自启动'), findsNothing);
    expect(find.text('悬浮导航栏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile settings links to the info page', (tester) async {
    FlvpPageKey? navigated;
    await pumpSettings(
      tester,
      platform: FlvpPlatform.mobile,
      width: 420,
      onNavigate: (key) => navigated = key,
    );

    expect(find.text('连接与日志'), findsOneWidget);
    await tester.tap(find.text('连接与日志'));
    await tester.pump();

    expect(navigated, FlvpPageKey.info);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps info out of the settings page', (tester) async {
    await pumpSettings(tester);

    expect(find.text('连接与日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary pages open with their own theme and store scopes', (
    tester,
  ) async {
    await pumpSettings(tester);

    Future<void> openAndBack(String row, String title) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(
        find.text(title),
        findsWidgets,
        reason: 'the $title page did not open',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回').last);
      await tester.pumpAndSettle();
    }

    await openAndBack('关于', '关于');
    await openAndBack('快捷键', '快捷键');
    await openAndBack('按需连接', '按需连接');
    await openAndBack('入站端口与认证', '入站端口与认证');
    await openAndBack('网络设置', '网络设置');
    await openAndBack('自定义资源', '自定义资源');
  });

  testWidgets('a pushed page can open its own dialogs', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('入站端口与认证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('混合端口'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('third level pages open from the network page', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('网络设置'));
    await tester.pumpAndSettle();

    Future<void> openAndBack(String row, String title) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(
        find.text(title),
        findsWidgets,
        reason: 'the $title page did not open',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回').last);
      await tester.pumpAndSettle();
    }

    await openAndBack('排除域名', '排除域名');
    await openAndBack('路由地址', '路由地址');
    await openAndBack('路由排除地址', '路由排除地址');
  });

  testWidgets('a third level page can add an entry', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('网络设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排除域名'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
