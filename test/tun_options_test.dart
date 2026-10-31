import 'dart:convert';

import 'package:flvpcore/core/compiler.dart';
import 'package:flvpcore/core/configuration_importer.dart';
import 'package:flvpcore/core/elevated_host.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = ConfigurationImporter();

  test('tun 字段按字段级降级，未支持字段单独提示', () {
    const text = '''
proxies:
  - {name: a, type: http, server: a.example.test, port: 8080}
tun:
  enable: true
  stack: mixed
  dns-hijack: [any:53]
  auto-route: true
  mtu: 1400
  mtu-future-key: 1
rules:
  - MATCH,DIRECT
''';
    final warnings = <String>[];
    final profile = importer.parse(text, name: 'tun', warnings: warnings);
    expect(profile.tun.enabled, isTrue);
    expect(profile.tun.autoRoute, isTrue);
    expect(profile.tun.mtu, 1400);
    expect(warnings.any((w) => w.contains('stack')), isTrue);
    expect(warnings.any((w) => w.contains('dns-hijack')), isTrue);
    expect(
      warnings.any((w) => w.contains('mtu-future-key') && w.contains('不受支持')),
      isTrue,
    );
  });

  test('编译输出携带 tun 运行时字段', () {
    final profile = importer.parse(
      jsonEncode({
        'proxies': [
          {'name': 'a', 'type': 'http', 'server': 'a.example.test', 'port': 8080},
        ],
        'tun': {'enable': true, 'auto-route': true},
      }),
      name: 'tun',
    );
    final compiled = const ConfigCompiler().compile(
      profile,
      mixedPort: 17890,
    );
    final tun =
        (jsonDecode(compiled.text) as Map<String, dynamic>)['tun']
            as Map<String, dynamic>;
    expect(tun['enable'], isTrue);
    expect(tun['auto-route'], isTrue);
    expect(tun['mtu'], 1500);
  });

  test('profile 序列化保留 tun', () {
    final profile = Profile(
      id: 'c40ba91d-1e63-46f0-8bab-74d0cb1159c0',
      displayName: 'tun',
      nodes: const [],
      rules: const [],
      tun: const TunOptions(enabled: true, mtu: 1280),
    );
    final restored = Profile.fromText(jsonEncode(profile.toJson()));
    expect(restored.tun.enabled, isTrue);
    expect(restored.tun.mtu, 1280);
  });

  test('TUN 模式编译出 fake-ip DNS', () {
    // 内核只把 fake-IP 网段路由进隧道。用 redir-host 会解析出真实 IP，
    // 流量走物理网卡，表现就是「TUN 开着但出口还是本机 IP」。
    final profile = importer.parse(
      jsonEncode({
        'proxies': [
          {'name': 'a', 'type': 'http', 'server': 'a.example.test', 'port': 8080},
        ],
        'tun': {'enable': true, 'auto-route': true},
      }),
      name: 'tun',
    );
    final compiled = const ConfigCompiler().compile(profile, mixedPort: 17890);
    final dns =
        (jsonDecode(compiled.text) as Map<String, dynamic>)['dns']
            as Map<String, dynamic>;
    expect(dns['enable'], isTrue);
    expect(dns['enhanced-mode'], 'fake-ip');
    expect(dns['fake-ip-range'], '198.18.0.0/16');
    // 未配置上游时必须有兜底，否则内核解析器没有可用服务器。
    expect(dns['nameserver'], isNotEmpty);
  });

  test('非 TUN 模式仍用 redir-host', () {
    final profile = importer.parse(
      jsonEncode({
        'proxies': [
          {'name': 'a', 'type': 'http', 'server': 'a.example.test', 'port': 8080},
        ],
        'tun': {'enable': false},
      }),
      name: 'tun',
    );
    final compiled = const ConfigCompiler().compile(profile, mixedPort: 17890);
    final dns =
        (jsonDecode(compiled.text) as Map<String, dynamic>)['dns']
            as Map<String, dynamic>;
    expect(dns['enhanced-mode'], isNot('fake-ip'));
    expect(dns.containsKey('fake-ip-range'), isFalse);
  });

  test('协助进程注册脚本包含开机自启、SYSTEM 与数据目录', () {
    final script = HelperClient.debugRegisterScript(
      r'C:\app\flvp-core-host.exe',
      r'C:\Users\u\AppData\Roaming\io.flvpcore\flvpcore',
    );
    expect(script, contains('-AtStartup'));
    expect(script, contains("'SYSTEM'"));
    expect(script, contains('RunLevel Highest'));
    expect(script, contains('--elevated-serve'));
    expect(script, contains('--app-support-dir'));
    // 常驻进程会被默认设置杀掉或拒启动，必须显式放开。
    expect(script, contains('-AllowStartIfOnBatteries'));
    expect(script, contains('-ExecutionTimeLimit'));
    expect(script, contains('Register-ScheduledTask'));
    // 注册即使失败也必须回写结果，而不是只依赖外壳进程退出码。
    expect(script, contains('ERR'));
    expect(HelperClient.debugUnregisterScript(), contains('Unregister-ScheduledTask'));
  });

  test('重新注册会先结束旧协助进程', () {
    // 旧进程占着网络锁与 TUN 路由；不结束它，新宿主的修复不会生效，
    // 界面会一直报「系统代理被另一个实例管理」。
    final script = HelperClient.debugRegisterScript(
      r'C:\app\flvp-core-host.exe',
      r'C:\support',
    );
    expect(script, contains('Stop-ScheduledTask'));
    expect(script, contains('Stop-Process'));
    expect(script, contains('flvp-core-host'));
    expect(
      script.indexOf('Stop-Process'),
      lessThan(script.indexOf('Register-ScheduledTask')),
      reason: '必须先停旧进程再注册新任务',
    );
  });

  test('协助进程跑在稳定目录，不占用构建产物', () {
    // 直接注册构建目录里的 exe，运行中的文件会被系统锁定，
    // 之后每次重建都无法覆盖，`flutter run` 会以 MSB3073 失败。
    const source = r'D:\repo\build\windows\x64\runner\Debug\flvp-core-host.exe';
    final script = HelperClient.debugRegisterScript(source, r'C:\support');
    expect(script, contains('Copy-Item'));
    expect(script, contains(HelperClient.helperDirectory.path));
    expect(
      script,
      contains("-Execute \$helperExe"),
      reason: '任务必须指向 ProgramData 下的副本',
    );
    expect(
      script,
      isNot(contains("-Execute '$source'")),
      reason: '不能把任务直接指向构建产物',
    );
    // wintun.dll 必须跟着副本走，否则 TUN 建不了卡。
    expect(script, contains('wintun.dll'));
  });
}
