import 'dart:io';

import 'package:floway/common/app_localizations.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/subscriptions/custom_page.dart';
import 'package:floway/ui/pages/subscriptions/edit_page.dart';
import 'package:floway/ui/pages/subscriptions/extend_page.dart';
import 'package:floway/ui/pages/subscriptions/profile_override_pages.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
import 'package:floway/ui/widgets/feedback.dart';
import 'package:floway/ui/widgets/page_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database_providers.dart';
import '../helpers/test_profiles.dart';

/// 编辑/覆写页在卸载时会安排一次自动应用；widget 测试里让它空转。
class _NoopSetupAction extends SetupAction {
  @override
  void autoApplyProfile() {}
}

Profile _profile(
  int id, {
  ProfileType type = ProfileType.url,
  String label = '配置1',
  String url = 'https://sub.example.com/link',
}) => Profile(
  id: id,
  label: label,
  type: type,
  url: type == ProfileType.url ? url : '',
  autoUpdateDuration: const Duration(hours: 12),
  lastUpdateDate: DateTime.now().subtract(const Duration(minutes: 5)),
);

void main() {
  late ProviderContainer container;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('floway_profile_pages');
    await useAppPaths(tempDir);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  void setUpContainer(
    List<Profile> profiles, {
    List<Override> overrides = const [],
  }) {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        setupActionProvider.overrideWith(() => _NoopSetupAction()),
        ...overrides,
      ],
    );
    globalState.container = container;
    container.listen(currentProfileIdProvider, (_, _) {});
    container.read(currentProfileIdProvider.notifier).value =
        profiles.firstOrNull?.id;
    addTearDown(container.dispose);
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = const Size(900, 1400);
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
                child: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => pushFlvpPage<void>(context, page),
                      child: const Text('打开'),
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
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('edit page edits the profile through the upstream actions', (
    tester,
  ) async {
    final profile = _profile(1, label: '旧名称');
    setUpContainer([profile]);

    await pumpPage(
      tester,
      FlvpProfileEditPage(profile: profile, platform: FlvpPlatform.pc),
    );

    expect(find.text('编辑配置'), findsOneWidget);
    expect(find.text('订阅地址'), findsOneWidget);
    expect(find.text('更新间隔'), findsOneWidget);
    expect(find.text('720 分钟'), findsOneWidget);
    // 关掉自动更新后，间隔行收起。
    await tester.tap(find.text('自动更新'));
    await tester.pump();
    expect(find.text('更新间隔'), findsNothing);

    // 名称为空时保存被拦下，并给出上游的校验文案。
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(
      find.text(currentAppLocalizations.profileNameNullValidationDesc),
      findsOneWidget,
    );
    expect(container.read(profilesProvider).first.label, '旧名称');

    // 改名后保存写回上游，并回到上一页。
    await tester.enterText(find.byType(TextField).first, '新名称');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(profilesProvider).first.label, '新名称');
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extend page switches the upstream extend type and lists rules', (
    tester,
  ) async {
    final profile = _profile(1);
    setUpContainer(
      [profile],
      overrides: [
        profileRulesProvider(1).overrideWith(_TestProfileRules.new),
        profileDisabledRuleIdsProvider(
          1,
        ).overrideWith(_TestDisabledRuleIds.new),
        clashConfigProvider(1).overrideWith((ref) async => const ClashConfig()),
        scriptsProvider.overrideWith(TestScripts.new),
      ],
    );

    await pumpPage(
      tester,
      const FlvpExtendPage(profileId: 1, platform: FlvpPlatform.pc),
    );

    expect(find.text('覆写'), findsOneWidget);
    expect(find.text('附加规则'), findsOneWidget);
    expect(find.text('匹配目标'), findsOneWidget);
    expect(container.read(profileProvider(1))?.extendType, ExtendType.standard);

    await tester.tap(find.text('脚本'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(profileProvider(1))?.extendType, ExtendType.script);
    expect(find.text('覆写脚本'), findsOneWidget);
    expect(find.text('管理脚本'), findsOneWidget);
    expect(find.text('附加规则'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a profile DNS override page writes into the profile overrides', (
    tester,
  ) async {    final profile = _profile(1);
    setUpContainer([profile]);

    await pumpPage(
      tester,
      const FlvpProfileDnsPage(profileId: 1, platform: FlvpPlatform.pc),
    );

    expect(find.text('DNS'), findsOneWidget);
    expect(find.text('还没有启用任何条目'), findsOneWidget);

    await tester.tap(find.byTooltip('添加条目'));
    await tester.pump();
    expect(find.text('IPv6'), findsWidgets);

    await tester.tap(find.text('IPv6').first);
    await tester.pump();

    expect(
      container.read(profilesProvider).first.overrides.dnsOverrideKeys.isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the custom workspace shell lists its sections and opens more', (
    tester,
  ) async {
    const profile = Profile(
      id: 7,
      label: '我的自定义',
      type: ProfileType.custom,
      autoUpdate: false,
      autoUpdateDuration: Duration(hours: 12),
    );
    setUpContainer(
      [profile],
      overrides: [
        customProfileDataProvider(
          7,
        ).overrideWith((ref) => const CustomProfileData()),
        proxyGroupsProvider(7).overrideWith(_TestProxyGroups.new),
        proxyDialersProvider(7).overrideWith(_TestProxyDialers.new),
        profileRulesProvider(7).overrideWith(_TestProfileRules.new),
        profileGroupsCountProvider(7).overrideWith((ref) => Stream.value(0)),
      ],
    );

    await pumpPage(
      tester,
      const FlvpCustomProfilePage(profileId: 7, platform: FlvpPlatform.pc),
    );

    expect(find.text('我的自定义'), findsOneWidget);
    expect(find.textContaining('自定义配置 · 0 个策略组'), findsOneWidget);
    for (final label in ['规则', '服务提供者', 'DNS', '更多']) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }

    // 「更多」页：拨号代理 / NTP / 嗅探 / TUN 四个分区。
    await tester.tap(find.text('更多').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('拨号代理'), findsOneWidget);
    expect(find.text('NTP'), findsOneWidget);
    expect(find.text('域名嗅探'), findsOneWidget);
    expect(find.text('TUN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestProfileRules extends ProfileRules {
  @override
  Stream<List<Rule>> build(int profileId) => Stream.value(const []);
}

class _TestDisabledRuleIds extends ProfileDisabledRuleIds {
  @override
  Stream<List<int>> build(int profileId) => Stream.value(const []);
}

class _TestProxyGroups extends ProxyGroups {
  @override
  Stream<List<ProxyGroup>> build(int profileId) => Stream.value(const []);
}

class _TestProxyDialers extends ProxyDialers {
  @override
  Stream<Map<int, String>> build(int profileId) => Stream.value(const {});
}
