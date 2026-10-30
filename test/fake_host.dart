import 'dart:async';
import 'dart:convert';

import 'package:flvpcore/core/transport.dart';

class FakeHost implements HostTransport {
  Map<String, dynamic> status = {
    'state': 'stopped',
    'generation': 0,
    'appliedRevision': 0,
    'configHash': null,
    'mixedPort': null,
    'upload': 0,
    'download': 0,
    'connections': 0,
    'selected': null,
  };
  bool failApply = false;
  bool supportsSystemProxy = false;
  bool failSystemProxy = false;
  Completer<void>? startGate;
  Completer<void>? startEntered;
  Completer<void>? applyGate;
  Completer<void>? applyEntered;
  final List<String> operations = [];

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async {
    final op = envelope['operation'] as String;
    operations.add(op);
    if (op == 'capabilities') {
      return {
        'ok': true,
        'result': {
          'protocolVersion': 1,
          'coreVersion': '1.1.0',
          'hostVersion': 'test',
          'systemProxy': supportsSystemProxy,
        },
      };
    }
    if (op == 'start') {
      startEntered?.complete();
      await startGate?.future;
    }
    if (op == 'enableSystemProxy' && failSystemProxy) {
      return {
        'ok': false,
        'status': Map<String, dynamic>.from(status),
        'error': {'code': 'SYSTEM_PROXY_FAILED', 'message': 'test WinINet failure'},
      };
    }
    if (op == 'apply' && applyGate != null) {
      applyEntered?.complete();
      await applyGate!.future;
      applyGate = null;
      applyEntered = null;
    }
    if (op == 'apply' && failApply) {
      status = {...status, 'generation': (status['generation'] as int) + 2};
      return {
        'ok': false,
        'status': status,
        'error': {
          'code': 'APPLY_FAILED',
          'message': 'test occupied port',
          'rollbackStatus': 'restored',
        },
      };
    }
    if (op == 'start' || op == 'apply') {
      final args = envelope['arguments'] as Map<String, Object?>;
      final config =
          jsonDecode(args['config'] as String) as Map<String, dynamic>;
      status = {
        ...status,
        'state': 'running',
        'generation': (status['generation'] as int) + 1,
        'appliedRevision': args['revision'],
        'configHash': args['configHash'],
        'mixedPort': config['mixed-port'],
      };
    } else if (op == 'enableSystemProxy') {
      status = {...status, 'systemProxy': true};
    } else if (op == 'disableSystemProxy') {
      status = {...status, 'systemProxy': false};
    } else if (op == 'stop') {
      status = {
        ...status,
        'state': 'stopped',
        'appliedRevision': 0,
        'configHash': null,
        'mixedPort': null,
        'systemProxy': false,
      };
    }
    return {'ok': true, 'result': Map<String, dynamic>.from(status)};
  }

  @override
  Future<void> close() async {}
}
