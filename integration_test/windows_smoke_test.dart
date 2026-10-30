import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/store/client_store.dart';
import 'package:flvpcore/ui/store/models.dart';

import 'capture.dart';

/// Verifies the production store behind the replicated design against the
/// real native host, including forwarding and failed-apply rollback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Design store drives real host; forwarding and rollback', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('flvp-ui-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    var c = ClientController(
      store: SnapshotStore(root),
      bridge: CoreBridge(
        Platform.isWindows
            ? WindowsHostTransport()
            : const AndroidHostTransport(),
      ),
    );
    var store = FlvpClientStore(c);
    await store.initializeClient();
    await c.save(c.profile, port: port);
    expect(c.error, isNull);
    await tester.pumpWidget(FlvpApp(store: store));
    await store.toggleRunning();
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.error, isNull);
    expect(store.running, isTrue);
    expect(find.text('已连接'), findsOneWidget);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) {
      request.response.write('FLVP_UI_FORWARDING_OK');
      request.response.close();
    });
    final client = await Socket.connect(InternetAddress.loopbackIPv4, port);
    client.write(
      'GET http://127.0.0.1:${origin.port}/verified HTTP/1.1\r\n'
      'Host: 127.0.0.1:${origin.port}\r\nConnection: close\r\n\r\n',
    );
    await client.flush();
    final response = await utf8.decoder
        .bind(client)
        .join()
        .timeout(const Duration(seconds: 5));
    expect(response, contains('FLVP_UI_FORWARDING_OK'));
    client.destroy();
    await origin.close(force: true);
    await c.refresh();
    expect(store.traffic.up + store.traffic.down, greaterThan(0));
    final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    store.setSettings((s) => s.copyWith(mixedPort: '${occupied.port}'));
    await store.flushSettings();
    expect(c.error, contains('已恢复上一配置'));
    expect(c.status.mixedPort, port);
    expect(store.settings.mixedPort, '$port');
    await occupied.close();
    await c.save(c.profile);
    if (Platform.isAndroid) {
      // A Flutter controller owns no Android runtime. Reattach to the
      // foreground service and verify that it retains its actual generation.
      final generation = c.status.generation;
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      c.dispose();
      c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(const AndroidHostTransport()),
      );
      store = FlvpClientStore(c);
      await store.initializeClient();
      expect(store.running, isTrue);
      expect(c.status.generation, generation);
    }
    store.setSettings((s) => s.copyWith(mode: FlvpProxyMode.global));
    await store.flushSettings();
    expect(store.settings.mode, FlvpProxyMode.global);
    await store.toggleRunning();
    expect(store.running, isFalse);
    await tester.pumpWidget(const SizedBox());
    await store.toggleRunning();
    expect(store.running, isTrue);
    await store.close();
    expect(c.status.running, isFalse);
    final released = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    await released.close();
    store.dispose();
    c.dispose();
    await root.delete(recursive: true);

    final artifacts = Platform.isWindows
        ? Directory('.artifacts/ui')
        : await getApplicationSupportDirectory();
    await captureShell(
      tester,
      shell: Platform.isAndroid ? FlvpShellKind.mobile : FlvpShellKind.desktop,
      file:
          '${artifacts.path}/${Platform.isAndroid ? 'android' : 'windows'}-dashboard.png',
    );
  });
}
