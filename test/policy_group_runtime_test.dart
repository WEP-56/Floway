import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flvpcore/ui/store/client_store.dart';

Future<ServerSocket> policyUpstream(String label) async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  listener.listen((socket) {
    var buffer = '', connected = false;
    socket.listen(
      (bytes) {
        buffer += utf8.decode(bytes);
        if (!connected && buffer.contains('\r\n\r\n')) {
          if (!buffer.startsWith('CONNECT ')) {
            socket.destroy();
            return;
          }
          buffer = buffer.substring(buffer.indexOf('\r\n\r\n') + 4);
          connected = true;
          socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        }
        if (connected && buffer.contains('\r\n\r\n')) {
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

Future<String> policyRequest(int port, String host) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(
    'GET http://$host/check HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
  );
  try {
    return await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 5));
  } finally {
    socket.destroy();
  }
}

void main() {
  final executable = File('native/core-host/target/debug/flvp-core-host.exe')
      .absolute;
  test(
    'policy selection, fallback, rule routing and restart use real upstreams',
    () async {
      final a = await policyUpstream('UPSTREAM_A'),
          b = await policyUpstream('UPSTREAM_B');
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final root = await Directory.systemTemp.createTemp(
        'flvp-policy-runtime-',
      );
      ClientController create() => ClientController(
        store: SnapshotStore(root),
        bridge: CoreBridge(
          WindowsHostTransport(
            executable: executable.path,
            supportDirectory: root.path,
          ),
        ),
      );
      var c = create();
      var store = FlvpClientStore(c);
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
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close();
      final document = {
        'proxies': [
          {'name': 'A', 'type': 'http', 'server': '127.0.0.1', 'port': a.port},
          {'name': 'B', 'type': 'http', 'server': '127.0.0.1', 'port': b.port},
          {
            'name': 'Dead',
            'type': 'http',
            'server': '127.0.0.1',
            'port': deadPort,
          },
        ],
        'proxy-groups': [
          {
            'name': 'Main',
            'type': 'select',
            'proxies': ['A', 'B'],
          },
          {
            'name': 'Backup',
            'type': 'fallback',
            'proxies': ['Dead', 'B'],
            'url': 'http://probe.invalid/health',
            'interval': 30,
            'lazy': false,
          },
          {
            'name': 'Fast',
            'type': 'url-test',
            'proxies': ['Dead', 'A'],
            'url': 'http://probe.invalid/health',
            'interval': 30,
            'tolerance': 0,
            'lazy': false,
          },
        ],
        'rules': [
          'DOMAIN,fallback.invalid,Backup',
          'DOMAIN,fast.invalid,Fast',
          'MATCH,Main',
        ],
      };
      await c.importConfiguration(
        'Policy',
        ConfigurationSourceKind.file,
        text: jsonEncode(document),
      );
      expect(c.error, isNull);
      await store.toggleRunning();
      expect(c.error, isNull);
      expect(
        await policyRequest(port, 'manual.invalid'),
        endsWith('UPSTREAM_A'),
      );
      expect(
        await policyRequest(port, 'fallback.invalid'),
        endsWith('UPSTREAM_B'),
      );
      // Failed first members must not prevent actual requests through either auto group.
      expect(await policyRequest(port, 'fast.invalid'), endsWith('UPSTREAM_A'));
      final group = c.profile.groups.first.id;
      final nodeB = c.profile.nodes[1].id;
      await store.selectGroupMember(group, nodeB);
      expect(c.error, isNull);
      expect(
        await policyRequest(port, 'manual.invalid'),
        endsWith('UPSTREAM_B'),
      );
      await c.close();
      store.dispose();
      c.dispose();
      c = create();
      store = FlvpClientStore(c);
      await store.initializeClient();
      expect(c.profile.groups.first.selectedId, nodeB);
      await store.toggleRunning();
      expect(c.error, isNull);
      expect(
        await policyRequest(port, 'manual.invalid'),
        endsWith('UPSTREAM_B'),
      );
    },
    skip: !Platform.isWindows || !executable.existsSync()
        ? 'Build Windows debug host first'
        : false,
  );
}
