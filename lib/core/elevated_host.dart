import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'transport.dart';

/// TUN 需要管理员权限。参考 FlClash 的 Helper 方案（services/helper：
/// Windows 服务 + 本地控制面），这里用「计划任务 + 回环 TCP」实现同样的体验：
/// 首次安装计划任务弹一次 UAC，之后以 SYSTEM 常驻，应用静默连接。
class HelperClient {
  static const taskName = 'FLVPcoreHelper';
  static const port = 38765;

  static Directory get directory => Directory(
    p.join(Platform.environment['ProgramData'] ?? r'C:\ProgramData', 'FLVPcore'),
  );

  static File get tokenFile => File(p.join(directory.path, 'token'));
  static File get endpointFile => File(p.join(directory.path, 'endpoint.json'));

  /// schtasks 创建参数：开机启动、SYSTEM 身份、最高权限。
  static List<String> createTaskArgs(String executable) => [
    '/Create',
    '/F',
    '/TN',
    taskName,
    '/SC',
    'ONSTART',
    '/RU',
    'SYSTEM',
    '/RL',
    'HIGHEST',
    '/TR',
    '"$executable" --elevated-serve',
  ];

  static List<String> deleteTaskArgs() => ['/Delete', '/F', '/TN', taskName];

  /// 需要提权时用 PowerShell 的 Start-Process -Verb RunAs 弹一次 UAC。
  static String elevatedCommand(List<String> arguments) {
    final quoted = arguments
        .map((item) => "'${item.replaceAll("'", "''")}'")
        .join(',');
    return 'Start-Process -FilePath schtasks.exe -ArgumentList $quoted '
        '-Verb RunAs -Wait -WindowStyle Hidden';
  }

  static Future<String?> readToken() async {
    try {
      final token = (await tokenFile.readAsString()).trim();
      return token.isEmpty ? null : token;
    } on FileSystemException {
      return null;
    }
  }

  static Future<bool> isInstalled() async {
    if (!Platform.isWindows) return false;
    final result = await Process.run('schtasks', [
      '/Query',
      '/TN',
      taskName,
    ], runInShell: false).catchError(
      (Object _) => ProcessResult(0, 1, '', ''),
    );
    return result.exitCode == 0;
  }

  /// 安装（首次弹 UAC）或启动已有的计划任务。
  static Future<void> ensureRunning(String executable) async {
    if (!Platform.isWindows) {
      throw const HostTransportException('TUN 仅支持 Windows');
    }
    if (!await isInstalled()) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        elevatedCommand(createTaskArgs(executable)),
      ]);
      if (result.exitCode != 0) {
        throw const HostTransportException('安装管理员协助进程失败或用户取消了授权');
      }
    }
    await Process.run('schtasks', ['/Run', '/TN', taskName], runInShell: false);
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await ping()) return;
    }
    throw const HostTransportException('管理员协助进程未能在 10 秒内就绪');
  }

  static Future<void> uninstall() async {
    if (!Platform.isWindows) return;
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      elevatedCommand(deleteTaskArgs()),
    ]);
  }

  static Future<bool> ping() async {
    final token = await readToken();
    if (token == null) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.write('${jsonEncode({'operation': 'hello', 'token': token})}\n');
      await socket.flush();
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      return jsonDecode(line)['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}

/// 通过回环 TCP 与常驻的管理员宿主对话；协议与 stdio 版本一致。
class ElevatedHostTransport implements HostTransport {
  ElevatedHostTransport({
    this.port = HelperClient.port,
    this.timeout = const Duration(seconds: 35),
  });

  final int port;
  final Duration timeout;
  Socket? _socket;
  final _lines = StreamController<String>.broadcast();
  bool _closed = false;

  Future<Socket> _connect() async {
    final token = await HelperClient.readToken();
    if (token == null) {
      throw const HostTransportException('未找到协助进程令牌，请重新启用 TUN');
    }
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_lines.add, onError: (Object _) {}, onDone: () {});
    socket.write('${jsonEncode({'operation': 'hello', 'token': token})}\n');
    await socket.flush();
    final ack = await _nextLine().timeout(const Duration(seconds: 5));
    if (jsonDecode(ack)['ok'] != true) {
      socket.destroy();
      throw const HostTransportException('协助进程拒绝了连接');
    }
    return socket;
  }

  Future<String> _nextLine() {
    final completer = Completer<String>();
    late StreamSubscription<String> subscription;
    subscription = _lines.stream.listen((line) {
      if (!completer.isCompleted) completer.complete(line);
      subscription.cancel();
    }, onError: (Object error) {
      if (!completer.isCompleted) {
        completer.completeError(HostTransportException('协助进程通信失败: $error'));
      }
      subscription.cancel();
    });
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async {
    if (_closed) throw const HostTransportException('宿主连接已关闭');
    _socket ??= await _connect();
    final pending = _nextLine();
    _socket!.write('${jsonEncode(envelope)}\n');
    await _socket!.flush();
    final line = await pending.timeout(timeout, onTimeout: () {
      throw const HostTransportException('协助进程响应超时');
    });
    return jsonDecode(line) as Map<String, dynamic>;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _socket?.destroy();
    _socket = null;
    await _lines.close();
  }
}
