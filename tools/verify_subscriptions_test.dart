// Opt-in real subscription probe. URLs arrive only via process environment;
// subscriptions, credentials and remote errors are never written or printed.
// This tests individual supported nodes, NOT complete Clash policy import.
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';

void main() {
  test('real subscription protocol probes (no system proxy changes)', () async {
    final bridge = CoreBridge(
      WindowsHostTransport(
        executable: File('native/core-host/target/debug/flvp-core-host.exe')
            .absolute
            .path,
      ),
    );
    addTearDown(bridge.close);
    await bridge.initialize();
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    var revision = 0;
    for (final label in ['A', 'B']) {
      final url = Platform.environment['FLVP_TEST_SUB_$label'];
      if (url == null) continue;
      final text = await const SubscriptionFetcher().fetch(url);
      var completeImport = false;
      try {
        const ConfigurationImporter().parse(text, name: 'probe');
        completeImport = true;
      } catch (_) {}
      final document = loadYaml(text) as Map;
      final protocols = <String, Map<String, int>>{};
      final probed = <String>{};
      for (final node in document['proxies'] as List) {
        final protocol = node['type'] as String;
        final counts = protocols.putIfAbsent(
          protocol,
          () => {
            'total': 0,
            'accepted': 0,
            'rejected': 0,
            'ready': 0,
            'connected': 0,
            'failed': 0,
            'tlsFailure': 0,
            'socketFailure': 0,
            'httpFailure': 0,
            'otherFailure': 0,
            'certificateFailure': 0,
            'timeout': 0,
            'curlConnected': 0,
            'curlFailed': 0,
          },
        );
        counts['total'] = counts['total']! + 1;
        try {
          final profile = const ConfigurationImporter().parse(
            jsonEncode({
              'proxies': [node],
            }),
            name: 'probe',
          );
          counts['accepted'] = counts['accepted']! + 1;
          if (!probed.add(protocol)) continue;
          final compiled = const ConfigCompiler().compile(
            profile,
            mixedPort: port,
            selectedNodeId: profile.nodes.single.id,
          );
          try {
            final snapshot = RuntimeSnapshot(
              revision: ++revision,
              config: compiled,
            );
            if (bridge.status.running) {
              await bridge.apply(snapshot);
            } else {
              await bridge.start(snapshot);
            }
            counts['ready'] = counts['ready']! + 1;
            final client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 10);
            client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
            try {
              final connected = await (() async {
                final request = await client.getUrl(
                  Uri.parse('https://example.com/'),
                );
                request.followRedirects = false;
                final response = await request.close();
                final bytes = <int>[];
                await for (final chunk in response) {
                  if (bytes.length + chunk.length > 65536) return false;
                  bytes.addAll(chunk);
                }
                return response.statusCode == 200 &&
                    utf8.decode(bytes).contains('Example Domain');
              })().timeout(const Duration(seconds: 15));
              counts[connected ? 'connected' : 'failed'] =
                  counts[connected ? 'connected' : 'failed']! + 1;
            } catch (error) {
              counts['failed'] = counts['failed']! + 1;
              final category = switch (error) {
                HandshakeException() => 'tlsFailure',
                SocketException() => 'socketFailure',
                HttpException() => 'httpFailure',
                _ => 'otherFailure',
              };
              counts[category] = counts[category]! + 1;
              if (error is HandshakeException &&
                  error.message.contains('CERTIFICATE_VERIFY_FAILED')) {
                counts['certificateFailure'] =
                    counts['certificateFailure']! + 1;
              }
              if (error is TimeoutException) {
                counts['timeout'] = counts['timeout']! + 1;
              }
            } finally {
              client.close(force: true);
            }
            // Independent HTTPS client distinguishes Dart client behavior from
            // outbound failure. Only a public test URL reaches the subprocess.
            final curl = await Process.run('curl.exe', [
              '--silent',
              '--show-error',
              '--max-time',
              '15',
              '--noproxy',
              '',
              '--proxy',
              'http://127.0.0.1:$port',
              '--write-out',
              '\n%{http_code}',
              'https://example.com/',
            ]);
            final curlOk =
                curl.exitCode == 0 &&
                (curl.stdout as String).contains('Example Domain') &&
                (curl.stdout as String).trim().endsWith('200');
            counts[curlOk ? 'curlConnected' : 'curlFailed'] = 1;
            if (!curlOk) counts['curlExitCode'] = curl.exitCode;
          } catch (_) {
            counts['failed'] = counts['failed']! + 1;
          }
        } catch (_) {
          counts['rejected'] = counts['rejected']! + 1;
        }
      }
      // Safe, bounded schema statistics only; never exception.toString().
      // ignore: avoid_print
      print(
        jsonEncode({
          'subscription': label,
          'completeImport': completeImport,
          'protocols': protocols,
        }),
      );
    }
    if (bridge.status.running) await bridge.stop();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
