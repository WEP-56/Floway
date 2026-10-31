import 'package:flvpcore/core/bridge.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapsTransport implements HostTransport {
  _CapsTransport(this.capabilities);
  final Map<String, Object?> capabilities;

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async => {
    'ok': true,
    'result': capabilities,
  };

  @override
  Future<void> close() async {}
}

void main() {
  test('旧宿主（缺少 contractVersion）直接报 HOST_OUTDATED', () async {
    final bridge = CoreBridge(
      _CapsTransport({'protocolVersion': 1, 'coreVersion': '1.1.0'}),
    );
    await expectLater(
      bridge.initialize(),
      throwsA(
        isA<CoreFailure>().having((e) => e.code, 'code', 'HOST_OUTDATED'),
      ),
    );
  });

  test('契约版本不符时报 HOST_OUTDATED 而不是继续启动', () async {
    final bridge = CoreBridge(
      _CapsTransport({'protocolVersion': 1, 'contractVersion': 1}),
    );
    await expectLater(
      bridge.initialize(),
      throwsA(
        isA<CoreFailure>().having((e) => e.code, 'code', 'HOST_OUTDATED'),
      ),
    );
  });
}
