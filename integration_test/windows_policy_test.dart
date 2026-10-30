import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/nav.dart';
import 'package:flvpcore/ui/store/client_store.dart';

import '../test/policy_group_runtime_test.dart'
    show policyUpstream, policyRequest;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows policy group UI changes actual forwarding', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('flvp-policy-ui-');
    final a = await policyUpstream('A'), b = await policyUpstream('B');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final c = ClientController(
      store: SnapshotStore(root),
      bridge: CoreBridge(WindowsHostTransport(supportDirectory: root.path)),
    );
    final store = FlvpClientStore(c);
    addTearDown(() async {
      await c.close();
      store.dispose();
      c.dispose();
      await a.close();
      await b.close();
      await root.delete(recursive: true);
    });
    await store.initializeClient();
    await c.save(c.profile, port: port);
    await c.importConfiguration(
      '本地策略验证',
      ConfigurationSourceKind.file,
      text: jsonEncode({
        'proxies': [
          {
            'name': '本地上游 A',
            'type': 'http',
            'server': '127.0.0.1',
            'port': a.port,
          },
          {
            'name': '本地上游 B',
            'type': 'http',
            'server': '127.0.0.1',
            'port': b.port,
          },
        ],
        'proxy-groups': [
          {
            'name': '默认出口',
            'type': 'select',
            'proxies': ['本地上游 A', '本地上游 B'],
          },
        ],
        'rules': ['MATCH,默认出口'],
      }),
    );
    expect(c.error, isNull);
    // The fixture imports through the controller to avoid a native file picker.
    // Sync the UI store through its normal selection action afterwards.
    await store.selectNode(c.selectedNodeId!);
    await store.toggleRunning();
    expect(c.error, isNull);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: FlvpApp(
          store: store,
          shell: FlvpShellKind.desktop,
          initialPage: FlvpPageKey.nodes,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(await policyRequest(port, 'test.invalid'), endsWith('A'));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地上游 B').last);
    await tester.pumpAndSettle();
    await store.flushSettings();
    expect(c.error, isNull);
    expect(c.profile.groups.single.selectedId, c.profile.nodes[1].id);
    expect(await policyRequest(port, 'test.invalid'), endsWith('B'));
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage(pixelRatio: 1);
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.artifacts/ui/windows-policy-groups.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    screenshot.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
