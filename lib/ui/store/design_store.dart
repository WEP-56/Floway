import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../design/accents.dart';
import 'models.dart';

/// A faithful port of the design's src/store.tsx: the same simulated traffic,
/// the same toast behaviour and the same action set, so every interaction of
/// the design can be reproduced without a core behind it.
class FlvpToastAction {
  const FlvpToastAction(this.label, this.run);

  final String label;
  final VoidCallback run;
}

class FlvpToast {
  const FlvpToast({required this.id, required this.message, this.action});

  final int id;
  final String message;
  final FlvpToastAction? action;
}

class FlvpTraffic {
  const FlvpTraffic({required this.up, required this.down});

  final double up;
  final double down;
}

/// Traffic accumulated before this session (used when stats scope = total).
const FlvpTraffic flvpHistoryBase = FlvpTraffic(up: 28.64, down: 173.25);

const int flvpHistLength = 48;

/// Floway 界面需要的最小后端能力：生产入口把界面动作转成上游能力，
/// 预览页与测试不注入后端，行为与设计稿一致。
abstract class FlvpBackend {
  Future<void> setRunning(bool value);

  Future<void> setSystemProxy(bool value);

  Future<void> setTunMode(bool value);

  Future<void> setMode(FlvpProxyMode value);

  Future<void> setCurrentProfile(String id);

  Future<void> addProfileFromLink(String url, String label);

  Future<void> deleteProfile(String id);

  Future<void> updateProfiles();

  /// 全部策略组测速；界面上的“测试延迟”按钮走这里。
  Future<void> testDelay();
}

class FlvpDesignStore extends ChangeNotifier {
  FlvpDesignStore({AppSettings? settings, bool simulate = true})
    : _simulate = simulate,
      _settings = settings ?? const AppSettings() {
    if (simulate) {
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      // 生产模式没有演示数据：内核还没上报前就该是 0，而不是设计稿的假数值。
      _clearRealtime();
    }
  }

  /// 是否跑设计稿的模拟数据；生产入口传 false。
  final bool _simulate;

  /// 生产入口注入的后端桥接；预览页与测试不注入。
  FlvpBackend? backend;

  AppSettings _settings;
  AppSettings get settings => _settings;

  bool running = true;
  int uptime = 2 * 3600 + 14 * 60 + 33;
  ({double up, double down}) speed = (up: 0, down: 0);
  late final Map<String, List<double>> hist = {
    'down': List.generate(
      flvpHistLength,
      (i) => 1800 + math.sin(i / 4) * 900 + _random.nextDouble() * 400,
    ),
    'up': List.generate(
      flvpHistLength,
      (i) => 220 + math.sin(i / 3) * 90 + _random.nextDouble() * 60,
    ),
  };
  ({double up, double down}) _session = (up: 1.24, down: 12.87);
  DateTime clock = DateTime.now();

  List<NodeInfo> nodes = List.of(flvpInitialNodes);
  List<PolicyGroupInfo> policyGroups = const [];
  Future<void> selectGroupMember(String groupId, String memberId) async {}
  String selectedNodeId = 'hk-01';
  bool testing = false;

  List<SubInfo> subs = List.of(flvpInitialSubs);

  /// Follows the platform when the theme mode is `system`, mirroring the
  /// `prefers-color-scheme` listener of the design.
  Brightness platformBrightness = Brightness.light;

  FlvpToast? toast;

  final math.Random _random = math.Random();
  Timer? _speedTimer;
  Timer? _toastTimer;
  var _speedUp = 0.0;
  var _speedDown = 0.0;

  bool get resolvedDark => switch (_settings.theme) {
    FlvpThemeMode.system => platformBrightness == Brightness.dark,
    FlvpThemeMode.light => false,
    FlvpThemeMode.dark => true,
  };

  FlvpAccent get accent => _settings.accent;

  /// 上游当前出口节点；为空时回落到演示节点，避免界面出现空值。
  NodeInfo? _backendNode;

  /// 第一帧真实流量到达前，曲线还是演示数据。
  bool _histPrimed = false;

  void _clearRealtime() {
    running = false;
    uptime = 0;
    speed = (up: 0, down: 0);
    _session = (up: 0, down: 0);
    for (final samples in hist.values) {
      samples.fillRange(0, samples.length, 0);
    }
  }

  NodeInfo get currentNode =>
      _backendNode ??
      (_simulate
          ? nodes.where((node) => node.id == selectedNodeId).firstOrNull ??
                nodes.first
          : flvpIdleNode);

  SubInfo get activeSub =>
      subs.where((sub) => sub.active).firstOrNull ??
      (subs.isEmpty ? flvpEmptySub : subs.first);

  FlvpTraffic get traffic => _settings.statsScope == FlvpStatsScope.total
      ? FlvpTraffic(
          up: _session.up + (_simulate ? flvpHistoryBase.up : 0),
          down: _session.down + (_simulate ? flvpHistoryBase.down : 0),
        )
      : FlvpTraffic(up: _session.up, down: _session.down);

  void setPlatformBrightness(Brightness value) {
    if (platformBrightness == value) return;
    platformBrightness = value;
    notifyListeners();
  }

  /* ---------- traffic simulation (store.tsx, 1 s interval) ---------- */

  void _tick() {
    clock = DateTime.now();
    if (!running) {
      _speedUp = 0;
      _speedDown = 0;
      speed = (up: 0, down: 0);
      _pushHistory();
      notifyListeners();
      return;
    }
    uptime += 1;
    final t = DateTime.now().millisecondsSinceEpoch / 1000;
    final targetDown = math.max(
      60,
      1750 + 2050 * math.sin(t / 6) + _random.nextDouble() * 850,
    );
    final targetUp = math.max(
      24,
      190 + 380 * math.sin(t / 4 + 1.2) + _random.nextDouble() * 140,
    );
    _speedDown += (targetDown - _speedDown) * 0.32;
    _speedUp += (targetUp - _speedUp) * 0.32;
    speed = (up: _speedUp, down: _speedDown);
    _pushHistory();
    _session = (
      up: _session.up + (_speedUp * 1024) / 1e9,
      down: _session.down + (_speedDown * 1024) / 1e9,
    );
    notifyListeners();
  }

  void _pushHistory() {
    hist['down'] = [...hist['down']!.skip(1), speed.down];
    hist['up'] = [...hist['up']!.skip(1), speed.up];
  }

  /* ---------- backend bridge ---------- */

  /// 后端的权威运行状态回推；不再反向调用后端。
  /// 后端的真实配置列表回推；当前配置由 active 标记。
  void syncProfiles(List<SubInfo> value) {
    subs = List.of(value);
    notifyListeners();
  }

  void syncRunning(bool value) {
    if (running == value) return;
    running = value;
    if (!running) uptime = 0;
    notifyListeners();
  }

  /// 上游策略组测速的权威状态回推，界面只反映它。
  void syncDelayTesting(bool value) {
    if (testing == value) return;
    testing = value;
    notifyListeners();
  }

  /// 上游实时速度（KB/s）回推，并推进曲线采样。
  void syncTraffic({required double upKb, required double downKb}) {
    speed = (up: upKb, down: downKb);
    if (!_histPrimed) {
      // 第一帧真实数据把演示曲线整条替换掉，避免残留假波形。
      hist['up']!.fillRange(0, hist['up']!.length, upKb);
      hist['down']!.fillRange(0, hist['down']!.length, downKb);
      _histPrimed = true;
    }
    _pushSample('up', upKb);
    _pushSample('down', downKb);
    notifyListeners();
  }

  /// 上游累计流量（GB）回推。
  void syncTotals({required double up, required double down}) {
    if (_session.up == up && _session.down == down) return;
    _session = (up: up, down: down);
    notifyListeners();
  }

  /// 上游运行时长（秒）回推。
  void syncUptime(int seconds) {
    if (uptime == seconds) return;
    uptime = seconds;
    notifyListeners();
  }

  /// 上游当前出口节点回推；传 null 表示内核没有可用节点。
  void syncCurrentNode(NodeInfo? value) {
    _backendNode = value;
    notifyListeners();
  }

  void _pushSample(String key, double value) {
    final samples = hist[key];
    if (samples == null || samples.isEmpty) return;
    samples
      ..removeAt(0)
      ..add(value);
  }

  /// 后端的权威快捷开关状态回推；不再反向调用后端。
  void syncShortcuts({bool? systemProxy, bool? tunMode, FlvpProxyMode? mode}) {
    final unchanged =
        (systemProxy == null || systemProxy == _settings.systemProxy) &&
        (tunMode == null || tunMode == _settings.tunMode) &&
        (mode == null || mode == _settings.mode);
    if (unchanged) return;
    _settings = _settings.copyWith(
      systemProxy: systemProxy,
      tunMode: tunMode,
      mode: mode,
    );
    notifyListeners();
  }

  /* ---------- actions ---------- */

  void toggleRunning() {
    final backend = this.backend;
    if (backend != null) {
      unawaited(backend.setRunning(!running));
      return;
    }
    if (!running) uptime = 0;
    final wasRunning = running;
    running = !running;
    notify(wasRunning ? '代理已停止' : '代理已启动');
  }

  void selectNode(String id) {
    selectedNodeId = id;
    final node = nodes.where((item) => item.id == id).firstOrNull;
    if (node == null) return;
    notify(node.id == 'auto' ? '已开启自动选择' : '已切换到 ${node.name}');
  }

  void testNodes() {
    final backend = this.backend;
    if (backend != null) {
      // 生产入口：交给上游策略组测速，testing 由 delayTestingGroups 回推。
      unawaited(backend.testDelay());
      return;
    }
    if (testing) return;
    testing = true;
    nodes = [for (final node in nodes) node.withLatency(null)];
    notifyListeners();
    Timer(const Duration(milliseconds: 1400), () {
      nodes = [
        for (final node in nodes)
          node.withLatency(
            node.id == 'auto'
                ? (12 + _random.nextDouble() * 36).round()
                : (6 + _random.nextDouble() * 210).round(),
          ),
      ];
      testing = false;
      notify('延迟测试完成');
    });
  }

  void activateSub(String id) {
    final backend = this.backend;
    if (backend != null) {
      unawaited(backend.setCurrentProfile(id));
      return;
    }
    subs = [for (final sub in subs) sub.copyWith(active: sub.id == id)];
    final target = subs.where((sub) => sub.id == id).firstOrNull;
    notify('已切换到「${target?.name ?? '订阅'}」');
  }

  void importSub(String name, String url) {
    final backend = this.backend;
    if (backend != null) {
      unawaited(backend.addProfileFromLink(url, name));
      return;
    }    subs = [
      ...subs,
      SubInfo(
        id: 's${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        url: url,
        used: 0,
        total: 100,
        expire: '2027-12-31',
        updated: '刚刚',
        active: subs.every((sub) => !sub.active),
      ),
    ];
    notify('已导入「$name」');
  }

  Future<bool> importRemoteConfiguration(String name, String url) async {
    importSub(name, url);
    return true;
  }

  Future<bool> importFileConfiguration(String name) async {
    notify('设计预览不读取本地文件');
    return false;
  }

  Future<bool> createManualConfiguration(
    String name,
    String protocol,
    String server,
    String port,
  ) async {
    notify('设计预览不保存配置');
    return false;
  }

  Future<void> copySubscriptionUrl(String id) async {
    notify('设计预览不复制订阅链接');
  }

  void removeSub(String id) {
    final backend = this.backend;
    if (backend != null) {
      unawaited(backend.deleteProfile(id));
      return;
    }    final snapshot = List.of(subs);
    final target = subs.where((sub) => sub.id == id).firstOrNull;
    final rest = subs.where((sub) => sub.id != id).toList();
    if ((target?.active ?? false) && rest.isNotEmpty) {
      rest[0] = rest[0].copyWith(active: true);
    }
    subs = rest;
    notify(
      '已删除「${target?.name ?? '订阅'}」',
      action: FlvpToastAction('撤销', () {
        subs = snapshot;
        notifyListeners();
      }),
    );
  }

  Future<void> refreshSub(String id) async {
    subs = [
      for (final sub in subs) sub.id == id ? sub.copyWith(updated: '刚刚') : sub,
    ];
    notify('订阅已更新');
  }

  void refreshAllSubs() {
    final backend = this.backend;
    if (backend != null) {
      unawaited(backend.updateProfiles());
      return;
    }    subs = [for (final sub in subs) sub.copyWith(updated: '刚刚')];
    notify('全部订阅已更新');
  }

  void setSettings(AppSettings Function(AppSettings current) mutate) {
    final before = _settings;
    _settings = mutate(_settings);
    final backend = this.backend;
    if (backend != null) {
      if (_settings.systemProxy != before.systemProxy) {
        unawaited(backend.setSystemProxy(_settings.systemProxy));
      }
      if (_settings.tunMode != before.tunMode) {
        unawaited(backend.setTunMode(_settings.tunMode));
      }
      if (_settings.mode != before.mode) {
        unawaited(backend.setMode(_settings.mode));
      }
    }
    notifyListeners();
  }

  /// 仅 Windows 宿主实现了管理员协助进程的卸载。
  Future<void> uninstallTunHelper() async {
    notify('当前环境不支持卸载管理员协助进程');
  }

  void toggleTheme() {
    setSettings(
      (current) => current.copyWith(
        theme: resolvedDark ? FlvpThemeMode.light : FlvpThemeMode.dark,
      ),
    );
  }

  /* ---------- toast (snackbar) ---------- */

  void notify(String message, {FlvpToastAction? action}) {
    toast = FlvpToast(
      id: DateTime.now().millisecondsSinceEpoch,
      message: message,
      action: action,
    );
    _toastTimer?.cancel();
    _toastTimer = Timer(
      Duration(milliseconds: action != null ? 4500 : 2400),
      () {
        toast = null;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void dismissToast() {
    _toastTimer?.cancel();
    toast = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }
}

/* ---------- formatters (store.tsx) ---------- */

({String value, String unit}) fmtSpeed(double kb) => kb >= 1024
    ? (value: (kb / 1024).toStringAsFixed(2), unit: 'MB/s')
    : (value: kb.toStringAsFixed(0), unit: 'KB/s');

String fmtGB(double gb) => gb >= 1024
    ? '${(gb / 1024).toStringAsFixed(2)} TB'
    : '${gb.toStringAsFixed(2)} GB';

String fmtUptime(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return [h, m, s].map((value) => value.toString().padLeft(2, '0')).join(':');
}

String fmtClock(DateTime time) => [
  time.hour,
  time.minute,
].map((value) => value.toString().padLeft(2, '0')).join(':');
