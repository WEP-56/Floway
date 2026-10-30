import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flvpcore/core/transport.dart';

import 'policy_groups_test.dart' show policyDocument;

void main() {
  final executable = File('native/core-host/target/debug/flvp-core-host.exe')
      .absolute;
  test(
    'Dart compiler and real Windows host agree on all protocol schemas',
    () async {
      final bridge = CoreBridge(
        WindowsHostTransport(executable: executable.path),
      );
      addTearDown(bridge.close);
      await bridge.initialize();
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = listener.port;
      await listener.close();
      final profile = const ConfigurationImporter().parse(
        await File('test/fixtures/subscriptions/advanced-nodes.json')
            .readAsString(),
        name: 'Synthetic',
      );
      final compiled = const ConfigCompiler().compile(
        profile,
        mixedPort: port,
        selectedNodeId: directTarget,
      );
      await bridge.start(RuntimeSnapshot(revision: 1, config: compiled));
      expect(bridge.status.running, isTrue);
      // All outbounds are eagerly constructed; no external servers are contacted.
      final malformed = jsonDecode(compiled.text) as Map<String, dynamic>;
      malformed['proxies'][0]['password'] = null;
      final text = jsonEncode(malformed);
      await expectLater(
        bridge.apply(
          RuntimeSnapshot(
            revision: 2,
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
      expect(bridge.status.running, isTrue);
      expect(bridge.status.appliedRevision, 1);
      final document = policyDocument();
      for (final node in document['proxies'] as List) {
        node['server'] = '127.0.0.1';
        node['port'] = 1;
      }
      for (final group in document['proxy-groups'] as List) {
        if (group['type'] != 'select') {
          group['url'] = 'http://127.0.0.1:1/check';
        }
      }
      final policy = const ConfigurationImporter().parse(
        jsonEncode(document),
        name: 'policy',
      );
      final policyConfig = const ConfigCompiler().compile(
        policy,
        mixedPort: port,
      );
      await bridge.apply(RuntimeSnapshot(revision: 3, config: policyConfig));
      expect(bridge.status.running, isTrue);
      final cycle = jsonDecode(policyConfig.text) as Map<String, dynamic>;
      cycle['proxy-groups'][1]['proxies'] = [cycle['proxy-groups'][1]['name']];
      final cycleText = jsonEncode(cycle);
      await expectLater(
        bridge.apply(
          RuntimeSnapshot(
            revision: 4,
            config: CompiledConfig(
              text: cycleText,
              runtimeHash: contentHash(cycleText),
              logicalHash: '',
              mixedPort: port,
            ),
          ),
        ),
        throwsA(isA<CoreFailure>()),
      );
      expect(bridge.status.appliedRevision, 3);
      await bridge.stop();
    },
    skip: !Platform.isWindows || !executable.existsSync()
        ? 'Build the Windows debug host to run this contract test'
        : false,
  );
}
