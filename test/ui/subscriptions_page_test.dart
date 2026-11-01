import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/subscriptions_page.dart';
import 'package:floway/ui/store/design_store.dart';
import 'package:floway/ui/store/store_scope.dart';
import 'package:floway/ui/widgets/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _gib = 1024 * 1024 * 1024;

Profile _profile(
  int id, {
  ProfileType type = ProfileType.url,
  SubscriptionInfo? info,
}) => Profile(
  id: id,
  label: '配置$id',
  type: type,
  url: type == ProfileType.url ? 'https://sub$id.example.com/link' : '',
  autoUpdateDuration: const Duration(hours: 12),
  lastUpdateDate: DateTime.now().subtract(const Duration(minutes: 5)),
  subscriptionInfo: info,
);

void main() {
  late ProviderContainer container;

  void setUpProfiles(List<Profile> profiles) {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
    );
    globalState.container = container;
    container.listen(currentProfileIdProvider, (_, _) {});
    container.read(currentProfileIdProvider.notifier).value =
        profiles.firstOrNull?.id;
    addTearDown(container.dispose);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    FlvpPlatform platform = FlvpPlatform.pc,
    double width = 900,
  }) async {
    tester.view.physicalSize = Size(width, 900);
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FlvpSubscriptionsPage(platform: platform),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says how to add a configuration when there is none', (
    tester,
  ) async {
    setUpProfiles([]);
    await pumpPage(tester);

    expect(find.text('暂无配置'), findsOneWidget);
    expect(find.textContaining('添加配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lists upstream profiles with quota, type and update time', (
    tester,
  ) async {
    final expire = DateTime.now().add(const Duration(days: 20));
    setUpProfiles([
      _profile(
        1,
        info: SubscriptionInfo(
          upload: 2 * _gib,
          download: 18 * _gib,
          total: 100 * _gib,
          expire: expire.millisecondsSinceEpoch ~/ 1000,
        ),
      ),
      _profile(2, type: ProfileType.file),
    ]);
    await pumpPage(tester);

    expect(find.text('配置1'), findsOneWidget);
    expect(find.text('配置2'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('远程'), findsOneWidget);
    expect(find.text('本地'), findsOneWidget);
    expect(find.textContaining('20 GB / 100 GB', findRichText: true), findsOneWidget);
    expect(find.textContaining('20 天后到期'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching a card writes the current profile upstream', (
    tester,
  ) async {
    setUpProfiles([_profile(1), _profile(2)]);
    await pumpPage(tester);

    expect(container.read(currentProfileIdProvider), 1);
    await tester.tap(find.text('切换'));
    await tester.pump();

    expect(container.read(currentProfileIdProvider), 2);
    // Let the snackbar timer of the switch notice run out.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card menu offers the upstream actions for a remote profile', (
    tester,
  ) async {
    setUpProfiles([_profile(1)]);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    for (final label in ['编辑', '覆写', '同步', '运行配置', '复制链接', '二维码分享', '导出文件', '删除']) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom profile renames instead of extending', (tester) async {
    setUpProfiles([
      const Profile(
        id: 7,
        label: '自定义',
        type: ProfileType.custom,
        autoUpdate: false,
        autoUpdateDuration: Duration(hours: 12),
      ),
    ]);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('覆写'), findsNothing);
    expect(find.text('同步'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
