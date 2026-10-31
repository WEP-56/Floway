import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/controller.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';

import 'policy_group_runtime_test.dart' show policyRequest, policyUpstream;
import 'dns_options_test.dart' show dnsDocument;

// Independent wire-format DNS fixture; only addresses in this test are served.
List<int> dnsAnswer(
  List<int> query,
  List<String> observed, {
  bool primary = false,
}) {
  var cursor = 12;
  final labels = <String>[];
  while (query[cursor] != 0) {
    final length = query[cursor++];
    labels.add(ascii.decode(query.sublist(cursor, cursor + length)));
    cursor += length;
  }
  final name = labels.join('.');
  observed.add(name);
  final end = cursor + 5;
  expect(query.sublist(cursor + 1, end), [0, 1, 0, 1]); // A / IN
  final missing = primary && name.startsWith('missing.');
  final address = primary && name.startsWith('poison.')
      ? [240, 0, 0, 1]
      : [127, 0, 0, 1];
  return [
    query[0],
    query[1],
    0x81,
    missing ? 0x83 : 0x80,
    0,
    1,
    0,
    missing ? 0 : 1,
    0,
    0,
    0,
    0,
    ...query.sublist(12, end),
    if (!missing) ...[0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 30, 0, 4, ...address],
  ];
}

void main() {
  final executable = File(
    Platform.environment['FLVP_TEST_HOST'] ??
        'native/core-host/target/debug/flvp-core-host.exe',
  ).absolute;
  test(
    'all DNS transport schemas compile and pass host preflight without querying',
    () async {
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
        jsonEncode(dnsDocument()),
        name: 'DNS transport contract',
      );
      final config = const ConfigCompiler().compile(profile, mixedPort: port);
      await bridge.start(RuntimeSnapshot(revision: 1, config: config));
      expect(bridge.status.running, true);
      await bridge.stop();
    },
    skip: !Platform.isWindows || !executable.existsSync()
        ? 'Build Windows host first'
        : false,
  );
  test(
    'Windows resolver uses configured DNS, filters, fallback, rollback and restart',
    () async {
      final primaryQueries = <String>[],
          fallbackQueries = <String>[],
          tcpQueries = <String>[];
      final primary = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final fallback = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      for (final (server, queries, isPrimary) in [
        (primary, primaryQueries, true),
        (fallback, fallbackQueries, false),
      ]) {
        server.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = server.receive();
          if (packet != null) {
            server.send(
              dnsAnswer(packet.data, queries, primary: isPrimary),
              packet.address,
              packet.port,
            );
          }
        });
      }
      final tcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>{};
      tcp.listen((socket) {
        sockets.add(socket);
        final buffer = <int>[];
        var sent = false;
        socket.listen(
          (bytes) {
            buffer.addAll(bytes);
            if (sent || buffer.length < 2) return;
            final length = (buffer[0] << 8) | buffer[1];
            if (buffer.length < length + 2) return;
            sent = true;
            final response = dnsAnswer(
              buffer.sublist(2, length + 2),
              tcpQueries,
            );
            socket.add([
              response.length >> 8,
              response.length & 255,
              ...response,
            ]);
            socket.close();
          },
          onError: (_) => socket.destroy(),
          onDone: () {
            sockets.remove(socket);
            socket.destroy();
          },
        );
      });
      var stalledConnections = 0;
      stalled.listen((socket) {
        sockets.add(socket);
        stalledConnections++;
        socket.listen(
          (_) {},
          onError: (_) => socket.destroy(),
          onDone: () {
            sockets.remove(socket);
            socket.destroy();
          },
        );
      });
      final upstream = await policyUpstream('DNS_PROXY_OK');
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((request) async {
        request.response.write('DNS_DIRECT_OK');
        await request.response.close();
      });
      var document = <String, dynamic>{
        'proxies': [
          {
            'name': 'DNS proxy',
            'type': 'http',
            'server': 'bootstrap.invalid',
            'port': upstream.port,
          },
        ],
        'dns': <String, dynamic>{
          'enable': true,
          'nameserver': ['127.0.0.1:${primary.port}'],
          'fallback': ['127.0.0.1:${fallback.port}'],
          'fallback-filter': {
            'geoip': false,
            'ipcidr': ['240.0.0.0/4'],
            'domain': ['+.force.invalid'],
          },
        },
      };
      final download = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      download.listen((request) async {
        request.response.write(jsonEncode(document));
        await request.response.close();
      });
      addTearDown(() async {
        primary.close();
        fallback.close();
        for (final socket in sockets.toList()) {
          socket.destroy();
        }
        await tcp.close();
        await stalled.close();
        await upstream.close();
        await origin.close(force: true);
        await download.close(force: true);
      });
      final root = await Directory.systemTemp.createTemp('flvp-dns-runtime-');
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
      var c = create();
      addTearDown(() async {
        await c.close();
        c.dispose();
        await root.delete(recursive: true);
      });
      Future<void> direct(String name) async {
        expect(
          await policyRequest(port, '$name:${origin.port}'),
          contains('DNS_DIRECT_OK'),
        );
      }

      await c.initialize();
      expect(c.error, null);
      expect(
        c.bridge.capabilities!['dnsResolver']['modes'],
        contains('redir-host'),
      );
      await c.save(c.profile, port: port);
      await c.importConfiguration(
        'DNS subscription',
        ConfigurationSourceKind.remote,
        url: 'http://127.0.0.1:${download.port}/subscription',
      );
      expect(c.error, null);
      final sourceId = c.library.activeId!, nodeId = c.selectedNodeId;
      await c.connect();
      expect(c.error, null);
      expect(
        await policyRequest(port, 'remote-destination.invalid'),
        contains('DNS_PROXY_OK'),
      );
      expect(primaryQueries, contains('bootstrap.invalid'));

      await c.save(c.profile.copyWith(mode: RoutingMode.direct));
      expect(c.error, null);
      await direct('normal.invalid');
      expect(primaryQueries, contains('normal.invalid'));
      await direct('poison.invalid');
      expect(primaryQueries, contains('poison.invalid'));
      expect(fallbackQueries, contains('poison.invalid'));
      await direct('sub.force.invalid');
      expect(primaryQueries, isNot(contains('sub.force.invalid')));
      expect(fallbackQueries, contains('sub.force.invalid'));
      await direct('missing.invalid');
      expect(primaryQueries, contains('missing.invalid'));
      expect(fallbackQueries, contains('missing.invalid'));

      document['mode'] = 'direct';
      document['dns']['nameserver'] = ['tcp://127.0.0.1:${tcp.port}'];
      await c.refreshConfiguration(sourceId);
      expect(c.error, null);
      expect(c.selectedNodeId, nodeId);
      await direct('tcp.invalid');
      expect(tcpQueries, contains('tcp.invalid'));

      final oldRevision = c.status.appliedRevision;
      final broken = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
      broken['dns']['nameserver'] = ['bogus host'];
      final valid = document;
      document = broken;
      await c.refreshConfiguration(sourceId);
      expect(c.error, isNotNull);
      expect(c.status.appliedRevision, oldRevision);
      await direct('after-rejected-update.invalid');

      // Bypass Dart validation to prove the host rejects bad DNS before stopping
      // the working runtime, rather than silently falling back to system DNS.
      final malformed = jsonDecode(
        c.compiler.compile(c.profile, mixedPort: port).text,
      );
      malformed['dns']['nameserver'] = ['tls://ignored.example.test'];
      final text = jsonEncode(malformed);
      await expectLater(
        c.bridge.apply(
          RuntimeSnapshot(
            revision: oldRevision + 1,
            config: CompiledConfig(
              text: text,
              runtimeHash: contentHash(text),
              logicalHash: '',
              mixedPort: port,
            ),
          ),
        ),
        throwsA(isA<CoreFailure>()),
      );
      expect(c.status.appliedRevision, oldRevision);
      await direct('after-host-rejection.invalid');

      document = valid;
      document['dns']['nameserver'] = ['tls://127.0.0.1:${stalled.port}'];
      await c.refreshConfiguration(sourceId);
      expect(c.error, null);
      final timer = Stopwatch()..start();
      await direct('dot-deadline.invalid');
      expect(stalledConnections, greaterThan(0));
      expect(timer.elapsedMilliseconds, inInclusiveRange(2500, 6000));
      expect(fallbackQueries, contains('dot-deadline.invalid'));

      document['dns']['nameserver'] = ['tcp://127.0.0.1:${tcp.port}'];
      await c.refreshConfiguration(sourceId);
      expect(c.error, null);
      await c.close();
      c.dispose();
      c = create();
      await c.initialize();
      expect(c.profile.dns.nameservers, ['tcp://127.0.0.1:${tcp.port}']);
      expect(c.selectedNodeId, nodeId);
      await c.connect();
      expect(c.error, null);
      await direct('after-restart.invalid');
      expect(tcpQueries, contains('after-restart.invalid'));
      await c.stop();
    },
    skip: !Platform.isWindows || !executable.existsSync()
        ? 'Build Windows host first'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
