import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flvpcore/core/elevated_host.dart';
import 'package:flvpcore/core/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按帮助进程的真实协议应答：先校验 hello+token，再逐行回包。
/// 用真实 socket 而不是桩对象，才能覆盖握手应答与响应竞争同一事件流的问题。
Future<ServerSocket> _startFakeHelper({
  required String token,
  required FutureOr<String> Function(String operation, Map<String, dynamic> req)
  respond,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    var authed = false;
    // 串行处理：IOSink.flush() 自己会绑定 sink，同一 socket 上并发 flush 会抛
    // StateError。真实协助进程也是单线程串行处理一条连接上的请求。
    var chain = Future<void>.value();
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          chain = chain.then((_) async {
            final value = jsonDecode(line) as Map<String, dynamic>;
            if (!authed) {
              final ok =
                  value['operation'] == 'hello' && value['token'] == token;
              authed = ok;
              socket.write(
                '${jsonEncode(ok ? {'ok': true, 'result': {'helper': true}} : {'ok': false, 'error': {'code': 'HELPER_UNAUTHORIZED'}})}\n',
              );
              return;
            }
            final payload = await respond(value['operation'] as String, value);
            socket.write('$payload\n');
          });
        });
  });
  return server;
}

void main() {
  test('握手令牌不匹配时拒绝连接', () async {
    final server = await _startFakeHelper(
      token: 'right',
      respond: (_, _) => '{"ok":true}',
    );
    final transport = ElevatedHostTransport(
      port: server.port,
      helperToken: 'wrong',
    );
    await expectLater(
      transport.request({'requestId': 'a', 'operation': 'status'}),
      throwsA(
        isA<HostTransportException>().having(
          (e) => e.message,
          'message',
          contains('拒绝'),
        ),
      ),
    );
    await transport.close();
    await server.close();
  });

  test('握手之后并发请求各自拿到自己的响应', () async {
    final server = await _startFakeHelper(
      token: 't',
      respond: (operation, req) =>
          jsonEncode({'requestId': req['requestId'], 'ok': true, 'result': operation}),
    );
    final transport = ElevatedHostTransport(port: server.port, helperToken: 't');
    // 并发是真实场景：状态轮询与用户操作用同一条连接。
    final responses = await Future.wait([
      transport.request({'requestId': 'r1', 'operation': 'capabilities'}),
      transport.request({'requestId': 'r2', 'operation': 'status'}),
      transport.request({'requestId': 'r3', 'operation': 'start'}),
    ]);
    expect(responses.map((r) => r['requestId']), ['r1', 'r2', 'r3']);
    expect(responses.map((r) => r['result']), ['capabilities', 'status', 'start']);
    await transport.close();
    await server.close();
  });

  test('协助进程无响应时给出可诊断的超时而不是空错误', () async {
    // 接受连接但永不回包。
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    server.listen(sockets.add);
    final transport = ElevatedHostTransport(
      port: server.port,
      helperToken: 't',
      timeout: const Duration(milliseconds: 300),
    );
    await expectLater(
      transport.request({'requestId': 'a', 'operation': 'status'}),
      throwsA(
        isA<HostTransportException>().having(
          (e) => e.message,
          'message',
          contains('未响应握手'),
        ),
      ),
    );
    await transport.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  });

  test('关闭后拒绝继续请求', () async {
    final transport = ElevatedHostTransport(port: 1, helperToken: 't');
    await transport.close();
    await expectLater(
      transport.request({'requestId': 'a', 'operation': 'status'}),
      throwsA(isA<HostTransportException>()),
    );
  });
}
