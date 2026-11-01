import 'package:floway/enum/enum.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:floway/ui/design/accents.dart';
import 'package:floway/ui/design/theme_scope.dart';
import 'package:floway/ui/design/tokens.dart';
import 'package:floway/ui/pages/info_page.dart';
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
    // Keep the feeds alive so records added below survive until the page reads.
    container.listen(logsProvider, (_, _) {});
    container.listen(requestsProvider, (_, _) {});
    container.listen(dnsQueriesProvider, (_, _) {});
    addTearDown(container.dispose);
  });

  void seed() {
    container.read(requestsProvider.notifier).addRequest(
      TrackerInfo(
        id: 'req-1',
        start: DateTime(2026, 11, 1, 19, 28, 30),
        metadata: const Metadata(network: 'tcp', host: 'example.com', destinationPort: '443'),
        chains: const ['Proxy'],
        rule: 'DomainSuffix',
        rulePayload: 'example.com',
      ),
    );
    container.read(dnsQueriesProvider.notifier).addQuery(
      DnsQuery(
        domain: 'example.com',
        type: 'A',
        time: DateTime(2026, 11, 1, 19, 28, 30),
        delay: 12,
        answers: const ['1.2.3.4'],
        rcode: 'NOERROR',
      ),
    );
    container.read(logsProvider.notifier).add(
      const Log(
        logLevel: LogLevel.error,
        payload: 'DNS resolution failed: example.com',
        dateTime: '2026-11-01 19:28:36.124',
      ),
    );
    container.read(logsProvider.notifier).add(
      const Log(
        logLevel: LogLevel.info,
        payload: 'Proxy server started successfully',
        dateTime: '2026-11-01 19:28:34.102',
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester, {FlvpPlatform platform = FlvpPlatform.pc}) async {
    tester.view.physicalSize = const Size(1000, 900);
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
                    child: FlvpInfoPage(platform: platform),
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

  testWidgets('opens on the connections tab with status and overview', (tester) async {
    seed();
    await pumpPage(tester);

    expect(find.text('连接'), findsOneWidget);
    expect(find.text('请求'), findsOneWidget);
    expect(find.text('DNS'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('实时连接'), findsOneWidget);
    expect(find.text('最近请求'), findsOneWidget);
    expect(find.text('日志记录'), findsOneWidget);
    expect(find.text('暂无实时连接'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('requests tab lists the seeded request', (tester) async {
    seed();
    await pumpPage(tester);

    await tester.tap(find.text('请求'));
    await tester.pump();
    expect(find.text('example.com:443'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('logs tab lists records and filters by level', (tester) async {
    seed();
    await pumpPage(tester);

    await tester.tap(find.text('日志'));
    await tester.pump();
    expect(find.text('DNS resolution failed: example.com'), findsOneWidget);
    expect(find.text('Proxy server started successfully'), findsOneWidget);

    // ERROR filter keeps only the error line (chip is the first ERROR text).
    await tester.tap(find.text('ERROR').first);
    await tester.pump();
    expect(find.text('DNS resolution failed: example.com'), findsOneWidget);
    expect(find.text('Proxy server started successfully'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dns tab exposes clear-cache action', (tester) async {
    seed();
    await pumpPage(tester);

    await tester.tap(find.text('DNS'));
    await tester.pump();
    expect(find.text('清除缓存'), findsOneWidget);
    expect(find.text('example.com'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });
}
