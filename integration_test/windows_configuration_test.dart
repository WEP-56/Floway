import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flvpcore/ui/store/client_store.dart';
import 'package:flvpcore/ui/app.dart';

import 'capture.dart';

Future<ServerSocket> upstream(String label) async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  listener.listen((socket) {
    var text = '';
    var connected = false;
    socket.listen(
      (bytes) {
        text += utf8.decode(bytes);
        if (!connected && text.contains('\r\n\r\n')) {
          final end = text.indexOf('\r\n\r\n') + 4;
          if (!text.startsWith('CONNECT ')) {
            socket.destroy();
            return;
          }
          text = text.substring(end);
          connected = true;
          socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        }
        if (connected && text.contains('\r\n\r\n')) {
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: ${label.length}\r\nConnection: close\r\n\r\n$label',
          );
          socket.close();
        }
      },
      onError: (_) => socket.destroy(),
      onDone: socket.destroy,
    );
  });
  return listener;
}

Future<String> request(int port) async {
  final client = await Socket.connect(InternetAddress.loopbackIPv4, port);
  client.write(
    'GET http://127.0.0.1:9/test HTTP/1.1\r\nHost: 127.0.0.1:9\r\nConnection: close\r\n\r\n',
  );
  await client.flush();
  try {
    return await utf8.decoder
        .bind(client)
        .join()
        .timeout(const Duration(seconds: 5));
  } finally {
    client.destroy();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows configurations select real upstreams and persist source snapshots',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'flvp-library-integration-',
      );
      final a = await upstream('SOURCE_A');
      final b = await upstream('SOURCE_B');
      final feed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var subscription = 'http://127.0.0.1:${b.port}#B';
      feed.listen((request) async {
        request.response.write(subscription);
        await request.response.close();
      });
      var c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(WindowsHostTransport(supportDirectory: root.path)),
      );
      var store = FlvpClientStore(c);
      addTearDown(() async {
        await c.close();
        store.dispose();
        c.dispose();
        await a.close();
        await b.close();
        await feed.close(force: true);
        await root.delete(recursive: true);
      });
      await store.initializeClient();
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      await c.save(c.profile, port: port);
      expect(
        await store.createManualConfiguration(
          'A',
          'http',
          '127.0.0.1',
          '${a.port}',
        ),
        isTrue,
      );
      final idA = c.library.activeId!;
      expect(
        await store.importRemoteConfiguration(
          'B',
          'http://127.0.0.1:${feed.port}/feed',
        ),
        isTrue,
      );
      final idB = c.library.sources.last.id;
      await tester.pumpWidget(
        FlvpApp(store: store, shell: FlvpShellKind.desktop),
      );
      await store.toggleRunning();
      expect(c.error, isNull);
      expect(await request(port), contains('SOURCE_A'));
      store.activateSub(idB);
      await store.flushSettings();
      expect(c.error, isNull);
      expect(c.library.activeId, idB);
      expect(store.nodes.where((n) => n.proto == 'HTTP').single.name, 'B');
      expect(await request(port), contains('SOURCE_B'));
      final oldNodeId = c.selectedNodeId;
      subscription = 'http://127.0.0.1:${b.port}#B-renamed';
      await store.refreshSub(idB);
      expect(c.error, isNull);
      expect(c.selectedNodeId, oldNodeId);
      expect(await request(port), contains('SOURCE_B'));
      subscription = 'ss://unsupported';
      await store.refreshSub(idB);
      expect(c.error, isNotNull);
      expect(c.library.activeId, idB);
      expect(await request(port), contains('SOURCE_B'));
      // The file source no longer depends on the original file after import.
      final file = File('${root.path}/import.txt');
      await file.writeAsString('http://127.0.0.1:${a.port}#file-A');
      await c.importConfiguration(
        'File',
        ConfigurationSourceKind.file,
        text: await file.readAsString(),
      );
      await file.delete();
      await tester.pumpWidget(const SizedBox());
      await c.close();
      store.dispose();
      c.dispose();
      c = ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(WindowsHostTransport(supportDirectory: root.path)),
      );
      store = FlvpClientStore(c);
      await store.initializeClient();
      expect(c.library.sources.length, 3);
      expect(c.library.activeId, idB);
      expect(c.library.sources.last.original, contains('file-A'));
      await store.toggleRunning();
      expect(await request(port), contains('SOURCE_B'));
      store.activateSub(idA);
      await store.flushSettings();
      expect(await request(port), contains('SOURCE_A'));
      await c.stop();
      await captureShell(
        tester,
        shell: FlvpShellKind.desktop,
        file: '.artifacts/ui/windows-tun-dashboard.png',
      );
    },
  );
}
