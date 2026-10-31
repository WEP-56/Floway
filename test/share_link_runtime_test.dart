import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';

import 'share_link_test.dart' show shareUuid, shareKey;

void main() {
  final executable = File('native/core-host/target/debug/flvp-core-host.exe')
      .absolute;
  final skip = !Platform.isWindows || !executable.existsSync()
      ? 'Build the Windows debug host to run this runtime test'
      : false;
  test('all new URI schemes pass real Windows host eager preflight', () async {
    final bridge = CoreBridge(
      WindowsHostTransport(executable: executable.path),
    );
    addTearDown(bridge.close);
    await bridge.initialize();
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final profile = const ConfigurationImporter().parse(
      [
        'vless://$shareUuid@127.0.0.1:1?security=reality&sni=tls.example.test&fp=chrome&pbk=$shareKey&sid=0123abcd',
        'vless://$shareUuid@127.0.0.1:2?security=tls&type=ws&sni=tls.example.test&host=ws.example.test&path=%2Fws&alpn=http%2F1.1',
        'trojan://sample@127.0.0.1:3?sni=tls.example.test',
        'hy2://sample@127.0.0.1:4?sni=tls.example.test',
      ].join('\n'),
      name: 'share links',
    );
    final compiled = const ConfigCompiler().compile(profile, mixedPort: port);
    await bridge.start(RuntimeSnapshot(revision: 1, config: compiled));
    expect(bridge.status.running, true);
    await bridge.stop();
  }, skip: skip);

  test('remote Base64 VLESS survives refresh failure and persisted restart', () async {
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>{};
    final observed = <String>[];
    addTearDown(() async {
      for (final socket in sockets.toList()) {
        socket.destroy();
      }
      await upstream.close();
    });
    // Minimal independent VLESS v0 peer: verify the wire credential and
    // destination rather than merely accepting a listener-ready result.
    upstream.listen((socket) {
      sockets.add(socket);
      final buffer = <int>[];
      var handshake = false, responded = false;
      socket.listen(
        (bytes) {
          buffer.addAll(bytes);
          if (!handshake && buffer.length >= 23) {
            expect(buffer[0], 0);
            expect(buffer.sublist(1, 17), [
              0x11,
              0x11,
              0x11,
              0x11,
              0x11,
              0x11,
              0x41,
              0x11,
              0x81,
              0x11,
              0x11,
              0x11,
              0x11,
              0x11,
              0x11,
              0x11,
            ]);
            expect(buffer[17], 0); // no flow addons
            expect(buffer[18], 1); // TCP
            expect(buffer.sublist(19, 21), [0, 80]);
            expect(buffer[21], 2); // domain
            final length = buffer[22];
            if (buffer.length < 23 + length) return;
            observed.add(utf8.decode(buffer.sublist(23, 23 + length)));
            buffer.removeRange(0, 23 + length);
            socket.add([0, 0]); // version and addons length
            handshake = true;
          }
          if (handshake &&
              !responded &&
              latin1.decode(buffer).contains('\r\n\r\n')) {
            responded = true;
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nVLESS_OK',
            );
            socket.close();
          }
        },
        onError: (_) => socket.destroy(),
        onDone: () {
          sockets.remove(socket);
          socket.destroy();
        },
      );
    });
    String link(String name) =>
        'vless://$shareUuid@127.0.0.1:${upstream.port}?encryption=none&type=tcp#${Uri.encodeComponent(name)}';
    var response = base64Encode(utf8.encode(link('first')));
    final download = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => download.close(force: true));
    download.listen((request) async {
      expect(request.headers.value(HttpHeaders.userAgentHeader), 'clash.meta');
      request.response.write(response);
      await request.response.close();
    });
    final root = await Directory.systemTemp.createTemp('flvp-share-runtime-');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    ClientController create() => ClientController(
      store: SnapshotStore(root),
      bridge: CoreBridge(
        WindowsHostTransport(
          executable: executable.path,
          supportDirectory: root.path,
        ),
      ),
    );
    var controller = create();
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await root.delete(recursive: true);
    });
    Future<void> forwards() async {
      final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
      try {
        final request = await client.getUrl(
          Uri.parse('http://payload.invalid/check'),
        );
        final result = await request.close().timeout(
          const Duration(seconds: 5),
        );
        expect(result.statusCode, 200);
        expect(await utf8.decoder.bind(result).join(), 'VLESS_OK');
        expect(observed.last, 'payload.invalid');
      } finally {
        client.close(force: true);
      }
    }

    await controller.initialize();
    await controller.save(controller.profile, port: port);
    await controller.importConfiguration(
      'remote links',
      ConfigurationSourceKind.remote,
      url: 'http://127.0.0.1:${download.port}/subscription',
    );
    expect(controller.error, null);
    final source = controller.library.active!;
    final nodeId = controller.selectedNodeId;
    await controller.connect();
    expect(controller.error, null);
    await forwards();

    response = base64Encode(utf8.encode(link('renamed')));
    await controller.refreshConfiguration(source.id);
    expect(controller.error, null);
    expect(controller.profile.nodes.single.displayName, 'renamed');
    expect(controller.selectedNodeId, nodeId);
    await forwards();

    final revision = controller.status.appliedRevision;
    response = '${link('valid')}\nhy2://sample@127.0.0.1:1?mport=443-8443';
    await controller.refreshConfiguration(source.id);
    expect(controller.error, contains('第 2 行'));
    expect(controller.status.appliedRevision, revision);
    expect(controller.profile.nodes.single.displayName, 'renamed');
    expect(controller.selectedNodeId, nodeId);
    await forwards();

    await controller.close();
    controller.dispose();
    controller = create();
    await controller.initialize();
    expect(controller.error, null);
    expect(controller.selectedNodeId, nodeId);
    expect(controller.profile.nodes.single.displayName, 'renamed');
    await controller.connect();
    expect(controller.error, null);
    await forwards();
    await controller.stop();
    expect(observed.length, 4);
  }, skip: skip);
}
