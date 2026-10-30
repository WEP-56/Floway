import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

abstract interface class HostTransport {
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope);
  Future<void> close();
}

class HostTransportException implements Exception {
  const HostTransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WindowsHostTransport implements HostTransport {
  WindowsHostTransport({
    String? executable,
    this.supportDirectory,
    this.timeout = const Duration(seconds: 35),
  }) : executable =
           executable ??
           Platform.environment['FLVP_CORE_HOST'] ??
           p.join(
             File(Platform.resolvedExecutable).parent.path,
             'flvp-core-host.exe',
           );

  final String executable;
  final String? supportDirectory;
  final Duration timeout;
  Process? _process;
  Future<void>? _starting;
  Future<void>? _recovering;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final List<String> _recentDiagnostics = [];
  bool _closed = false;

  Future<void> _ensureStarted() async {
    if (_closed) throw const HostTransportException('宿主连接已关闭');
    await _recovering;
    if (_process != null) return;
    await (_starting ??= _start().whenComplete(() => _starting = null));
  }

  Future<void> _start() async {
    if (!p.isAbsolute(executable) || !await File(executable).exists()) {
      throw const HostTransportException(
        '未找到原生宿主，请先运行 tools/build_windows.ps1',
      );
    }
    final process = await Process.start(
      executable,
      [],
      runInShell: false,
      workingDirectory: File(executable).parent.path,
      environment: {
        ...Platform.environment,
        'FLVP_APP_SUPPORT_DIR': ?supportDirectory,
      },
    );
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final map = jsonDecode(line) as Map<String, dynamic>;
              _pending.remove(map['requestId'])?.complete(map);
            } catch (_) {
              _failPending(const HostTransportException('宿主返回了无效协议帧'));
              process.kill();
            }
          },
          onError: (Object error) {
            _failPending(const HostTransportException('宿主输出读取失败'));
            process.kill();
          },
        );
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          _recentDiagnostics.add(line);
          if (_recentDiagnostics.length > 100) _recentDiagnostics.removeAt(0);
        }, onError: (Object _) {});
    unawaited(
      process.exitCode.then((_) async {
        if (identical(_process, process)) _process = null;
        // A fresh recovery-only process owns the same lock and journal. It
        // covers host crashes/forced termination while the Flutter UI is alive.
        final recovery = _recoverSystemProxy();
        _recovering = recovery;
        try {
          await recovery;
          _failPending(const HostTransportException('原生宿主已退出，代理已停止'));
        } catch (_) {
          _failPending(
            const HostTransportException(
              '原生宿主已退出；系统代理恢复失败或设置已被外部修改，请重新连接查看恢复状态',
            ),
          );
        } finally {
          if (identical(_recovering, recovery)) _recovering = null;
        }
      }),
    );
  }

  Future<void> _recoverSystemProxy() async {
    if (supportDirectory == null) return;
    final process = await Process.start(
      executable,
      ['--recover-system-proxy'],
      runInShell: false,
      environment: {'FLVP_APP_SUPPORT_DIR': supportDirectory!},
    );
    final stdoutDrain = process.stdout.drain<void>();
    final stderrDrain = process.stderr.drain<void>();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        throw const HostTransportException('系统代理恢复超时，日志已保留');
      },
    );
    await Future.wait([stdoutDrain, stderrDrain]);
    if (exitCode != 0) {
      throw const HostTransportException('系统代理恢复失败，恢复日志已保留');
    }
  }

  void _failPending(Object error) {
    final waiters = _pending.values.toList();
    _pending.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async {
    try {
      await _ensureStarted();
    } on ProcessException {
      throw const HostTransportException('无法启动原生宿主，请检查安装文件');
    } on FileSystemException {
      throw const HostTransportException('无法访问原生宿主安装目录');
    }
    final id = envelope['requestId'] as String;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      _process!.stdin.writeln(jsonEncode(envelope));
      await _process!.stdin.flush();
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          // Terminate the owned process on ambiguous timeout; do not leave an
          // unobserved listener running or blindly replay a mutation.
          _process?.kill();
          throw const HostTransportException('宿主响应超时，已终止本实例；请重试连接');
        },
      );
    } on IOException {
      _process?.kill();
      throw const HostTransportException('宿主通信中断，已停止本实例；请重试连接');
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final process = _process;
    if (process == null) {
      await _recovering;
      return;
    }
    await process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
    await _recovering;
  }
}

class AndroidHostTransport implements HostTransport {
  const AndroidHostTransport();
  static const _channel = MethodChannel('io.flvpcore/core');

  @override
  Future<Map<String, dynamic>> request(Map<String, Object?> envelope) async {
    try {
      final text = await _channel.invokeMethod<String>(
        'request',
        jsonEncode(envelope),
      );
      if (text == null) {
        throw const HostTransportException('Android 原生服务没有返回结果');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on PlatformException catch (error) {
      throw HostTransportException(error.message ?? 'Android 原生服务不可用');
    } on MissingPluginException {
      throw const HostTransportException('未安装 Android 原生宿主');
    }
  }

  @override
  Future<void> close() async {
    // Activity detachment must not stop a foreground proxy service.
  }
}
