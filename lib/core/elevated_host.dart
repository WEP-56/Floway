import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'transport.dart';

/// TUN 需要管理员权限。参考 FlClash 的 Helper 方案（services/helper：
/// Windows 服务 + 本地控制面），这里用「计划任务 + 回环 TCP」实现同样的体验：
/// 首次安装计划任务弹一次 UAC，之后以 SYSTEM 常驻，应用静默连接。
///
/// 注册务必走脚本文件而不是命令行拼串：`schtasks /TR` 的值里既有空格又有
/// 引号，经 `Start-Process -ArgumentList` 数组拼接后会被拆成两个参数，
/// schtasks 报 `Invalid argument/option - '--elevated-serve'` 并且退出码
/// 被 Start-Process 吞掉——表现为 UAC 弹窗正常、任务从未建立、界面一直等到超时。
class HelperClient {
  static const taskName = 'FLVPcoreHelper';
  static const port = 38765;

  /// 由本应用写入、用于判断已注册任务是否仍然指向当前的宿主与数据目录。
  static const _stampName = 'helper-task.json';

  static Directory get directory => Directory(
    p.join(Platform.environment['ProgramData'] ?? r'C:\ProgramData', 'FLVPcore'),
  );

  /// 协助进程运行的稳定目录。绝不能用构建产物：运行中的 exe 会被系统锁定，
  /// 之后每次重建都无法覆盖，`flutter run` 会以 MSB3073 失败。
  static Directory get helperDirectory =>
      Directory(p.join(directory.path, 'helper'));

  static File get helperExecutable =>
      File(p.join(helperDirectory.path, 'flvp-core-host.exe'));

  static File get tokenFile => File(p.join(directory.path, 'token'));
  static File get endpointFile => File(p.join(directory.path, 'endpoint.json'));
  static File get _stampFile => File(p.join(directory.path, _stampName));

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

  /// 已注册任务是否仍指向当前宿主二进制与数据目录，且常驻进程确实是这份二进制。
  ///
  /// 只比路径不够：重新构建后路径没变，旧版本的协助进程会一直跑下去，
  /// 于是新宿主的修复永远不生效（表现为锁一直被老进程占着）。
  static Future<bool> _stampMatches(
    String executable,
    String supportDirectory,
    DateTime executableModified,
  ) async {
    try {
      final stamp =
          jsonDecode(await _stampFile.readAsString()) as Map<String, dynamic>;
      if (stamp['executable'] != executable ||
          stamp['supportDirectory'] != supportDirectory) {
        return false;
      }
      // 源 exe 变了（重新构建）就必须重新拷贝并重启协助进程。
      final recorded = DateTime.tryParse('${stamp['executableModified']}');
      if (recorded == null ||
          !recorded.isAtSameMomentAs(executableModified.toUtc())) {
        return false;
      }
      final copy = helperExecutable;
      if (!copy.existsSync()) return false;
      // 正在跑的进程必须就是磁盘上这份副本，否则它仍是旧版本。
      final live = await _liveBinaryModified();
      if (live == null) return false;
      return live == copy.statSync().modified.toUtc().millisecondsSinceEpoch;
    } catch (_) {
      return false;
    }
  }

  /// 询问常驻进程正在运行的二进制修改时间（Unix 毫秒）；连不上返回 null。
  static Future<int?> _liveBinaryModified() async {
    final token = await readToken();
    if (token == null) return null;
    try {
      final response = await _control({'operation': 'hello', 'token': token});
      if (response['ok'] != true) return null;
      final result = response['result'];
      if (result is! Map) return null;
      final value = result['exeModifiedMs'];
      return value is int ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// 安装（首次弹 UAC）或启动已有的计划任务。
  static Future<void> ensureRunning(
    String executable, {
    required String supportDirectory,
  }) async {
    if (!Platform.isWindows) {
      throw const HostTransportException('TUN 仅支持 Windows');
    }
    final stat = File(executable).statSync();
    final installed = await isInstalled();
    final current = installed &&
        await _stampMatches(executable, supportDirectory, stat.modified);
    if (!current) {
      // 旧协助进程必须先在提权脚本里结束：它可能占着网络锁和 TUN 路由。
      await _runElevated(
        _registerScript(executable, supportDirectory),
        '安装',
      );
      await _stampFile.parent.create(recursive: true);
      await _stampFile.writeAsString(
        jsonEncode({
          'executable': executable,
          'supportDirectory': supportDirectory,
          'executableModified': stat.modified.toUtc().toIso8601String(),
          'registeredAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } else {
      // 任务已在，直接触发启动；已常驻时 Start-ScheduledTask 是空操作。
      await Process.run('schtasks', [
        '/Run',
        '/TN',
        taskName,
      ], runInShell: false);
    }
    await _waitForHelper();
  }

  /// 发一条控制面请求并读回一行应答。
  static Future<Map<String, dynamic>> _control(
    Map<String, Object?> payload,
  ) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 2),
    );
    final frames = StreamIterator(
      socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter()),
    );
    try {
      socket.write('${jsonEncode(payload)}\n');
      if (!await frames.moveNext().timeout(const Duration(seconds: 2))) {
        throw const HostTransportException('协助进程没有应答');
      }
      return jsonDecode(frames.current) as Map<String, dynamic>;
    } finally {
      await frames.cancel();
      socket.destroy();
    }
  }

  static Future<void> _waitForHelper() async {
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await ping()) return;
    }
    throw const HostTransportException(
      '管理员协助进程未能在 15 秒内就绪。可在「设置 · TUN」卸载协助进程后重试，'
      '并检查 Windows 事件查看器中的计划任务记录',
    );
  }

  static Future<void> uninstall() async {
    if (!Platform.isWindows) return;
    await _runElevated(_unregisterScript(), '卸载');
    try {
      await _stampFile.delete();
    } on FileSystemException {
      // 任务已经卸载，标记缺失不影响后续重新安装。
    }
  }

  /// 把脚本写到文件后以管理员身份执行，并通过结果文件回传真实退出原因。
  /// 命令行里只有脚本路径，不拼接任何业务参数，避免引号被层层重解析。
  static Future<void> _runElevated(String script, String action) async {
    await directory.create(recursive: true);
    final scriptFile = File(p.join(directory.path, 'helper-task.ps1'));
    final resultFile = File(p.join(directory.path, 'helper-task.result'));
    if (resultFile.existsSync()) await resultFile.delete();
    // Windows PowerShell 5.1 只有带 BOM 的 UTF-8 才能正确读出非 ASCII 路径。
    await scriptFile.writeAsBytes([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(script),
    ]);
    final launcher =
        "Start-Process -FilePath 'powershell.exe' -ArgumentList "
        "'-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "
        '"${scriptFile.path}"\' -Verb RunAs -Wait';
    final process = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      launcher,
    ]);
    final stderr = '${process.stderr}'.trim();
    if (process.exitCode != 0) {
      throw HostTransportException(
        '$action管理员协助进程失败或用户取消了授权${stderr.isEmpty ? '' : '：$stderr'}',
      );
    }
    String detail = '';
    try {
      detail = (await resultFile.readAsString()).replaceFirst('\uFEFF', '').trim();
    } on FileSystemException {
      throw HostTransportException('$action管理员协助进程失败：脚本没有返回结果');
    }
    if (!detail.startsWith('OK')) {
      throw HostTransportException(
        '$action管理员协助进程失败：${detail.replaceFirst(RegExp(r'^ERR\s*'), '')}',
      );
    }
  }

  static String _registerScript(String executable, String supportDirectory) => '''\$ErrorActionPreference = 'Stop'
\$result = '${_escape(p.join(directory.path, 'helper-task.result'))}'
try {
  Import-Module ScheduledTasks -ErrorAction Stop
  # 先结束可能还在跑的老协助进程：它占着网络锁和 TUN 路由，
  # 不结束的话新宿主的修复不会生效，界面会一直报「被另一个实例管理」。
  Get-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue |
    Stop-ScheduledTask -ErrorAction SilentlyContinue
  Get-Process -Name 'flvp-core-host' -ErrorAction SilentlyContinue |
    Where-Object { \$_.Id -ne \$PID } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300

  # 协助进程必须跑在稳定的独立目录里，不能直接用构建产物：
  # 正在运行的 exe 会被系统锁定，之后每次重建都无法覆盖它，构建直接失败。
  \$helperDir = '${_escape(helperDirectory.path)}'
  New-Item -ItemType Directory -Force -Path \$helperDir | Out-Null
  \$helperExe = Join-Path \$helperDir 'flvp-core-host.exe'
  Copy-Item -LiteralPath '${_escape(executable)}' -Destination \$helperExe -Force
  \$driver = Join-Path '${_escape(p.dirname(executable))}' 'wintun.dll'
  if (Test-Path -LiteralPath \$driver) {
    Copy-Item -LiteralPath \$driver -Destination \$helperDir -Force
  }

  \$action = New-ScheduledTaskAction -Execute \$helperExe `
    -Argument '--elevated-serve --app-support-dir "${_escape(supportDirectory)}"'
  \$trigger = New-ScheduledTaskTrigger -AtStartup
  \$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest
  # 默认任务会在电池供电时拒绝启动、并在 72 小时后被强制结束，
  # 两者都会让常驻协助进程悄悄消失。
  \$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
  Register-ScheduledTask -TaskName '$taskName' -Action \$action -Trigger \$trigger `
    -Principal \$principal -Settings \$settings -Force | Out-Null
  Start-ScheduledTask -TaskName '$taskName'
  'OK' | Set-Content -LiteralPath \$result -Encoding UTF8
} catch {
  "ERR \$(\$_.Exception.Message)" | Set-Content -LiteralPath \$result -Encoding UTF8
  exit 1
}
''';

  static String _unregisterScript() => '''
\$ErrorActionPreference = 'Stop'
\$result = '${_escape(p.join(directory.path, 'helper-task.result'))}'
try {
  Import-Module ScheduledTasks -ErrorAction Stop
  Stop-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:\$false
  Get-Process -Name 'flvp-core-host' -ErrorAction SilentlyContinue |
    Where-Object { \$_.Id -ne \$PID } | Stop-Process -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath '${_escape(helperDirectory.path)}' -Recurse -Force -ErrorAction SilentlyContinue
  'OK' | Set-Content -LiteralPath \$result -Encoding UTF8
} catch {
  "ERR \$(\$_.Exception.Message)" | Set-Content -LiteralPath \$result -Encoding UTF8
  exit 1
}
''';

  /// PowerShell 单引号字符串里只有 '' 需要转义。
  static String _escape(String value) => value.replaceAll("'", "''");

  /// 仅供测试断言脚本内容，不参与运行逻辑。
  static String debugRegisterScript(String executable, String supportDir) =>
      _registerScript(executable, supportDir);

  static String debugUnregisterScript() => _unregisterScript();

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
    String? helperToken,
  }) : _token = helperToken;

  final int port;
  final Duration timeout;

  /// 仅供测试注入；生产路径一律读取协助进程写入的共享令牌。
  final String? _token;
  Socket? _socket;
  Future<Socket>? _connecting;

  /// 已到达但还没被取走的行。广播流不缓存，握手应答与响应都必须排队读，
  /// 否则两者竞争同一个事件，先到的会被丢掉。
  final _queue = <String>[];
  final _waiters = <Completer<String>>[];
  Object? _failure;
  bool _closed = false;
  String _partial = '';

  void _onChunk(String chunk) {
    _partial += chunk;
    for (var index = _partial.indexOf('\n'); index >= 0;
        index = _partial.indexOf('\n')) {
      final line = _partial.substring(0, index).trim();
      _partial = _partial.substring(index + 1);
      if (line.isEmpty) continue;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(line);
      } else {
        _queue.add(line);
      }
    }
  }

  void _onFailure(Object error) {
    _failure = error;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(HostTransportException('协助进程通信失败: $error'));
      }
    }
    _waiters.clear();
  }

  Future<String> _nextLine(Duration limit, String onTimeout) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    if (_failure != null) {
      return Future.error(HostTransportException('协助进程通信失败: $_failure'));
    }
    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future.timeout(
      limit,
      onTimeout: () {
        _waiters.remove(completer);
        throw HostTransportException(onTimeout);
      },
    );
  }

  Future<Socket> _connect() async {
    final token = _token ?? await HelperClient.readToken();
    if (token == null) {
      throw const HostTransportException('未找到协助进程令牌，请重新启用 TUN');
    }
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    );
    // 直接用 Socket 自身的流：`cast()` 会把 socket 的 sink 绑定到该流，
    // 之后再也无法写入。
    const decoder = Utf8Decoder(allowMalformed: true);
    socket.listen(
      (List<int> chunk) => _onChunk(decoder.convert(chunk)),
      onError: (Object error) => _onFailure(error),
      onDone: () => _onFailure('连接已断开'),
    );
    socket.write('${jsonEncode({'operation': 'hello', 'token': token})}\n');
    final ack = await _nextLine(
      const Duration(seconds: 5),
      '协助进程未响应握手；请确认协助进程仍在运行',
    );
    if (jsonDecode(ack)['ok'] != true) {
      socket.destroy();
      throw const HostTransportException('协助进程拒绝了连接');
    }
    return socket;
  }

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async {
    if (_closed) throw const HostTransportException('宿主连接已关闭');
    // 并发调用只建立一条连接；切换 transport 后首个请求负责握手。
    final socket = _socket ?? await (_connecting ??= _connect().then((socket) {
      _socket = socket;
      return socket;
    }).whenComplete(() => _connecting = null));
    final pending = _nextLine(
      timeout,
      '协助进程响应超时；请确认协助进程仍在运行（可在设置中重新启用 TUN）',
    );
    // 不调用 flush()：IOSink.flush 自己会临时绑定 sink，并发请求时互相冲突
    // （StateError: StreamSink is bound to a stream）。Socket 的写入本就按序缓冲。
    socket.write('${jsonEncode(envelope)}\n');
    final line = await pending;
    return jsonDecode(line) as Map<String, dynamic>;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _socket?.destroy();
    _socket = null;
    _onFailure('连接已关闭');
  }
}
