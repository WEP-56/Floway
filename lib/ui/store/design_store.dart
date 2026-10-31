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

class FlvpDesignStore extends ChangeNotifier {
  FlvpDesignStore({AppSettings? settings, bool simulate = true})
    : _settings = settings ?? const AppSettings() {
    if (simulate) {
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

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

  NodeInfo get currentNode =>
      nodes.where((node) => node.id == selectedNodeId).firstOrNull ??
      nodes.first;

  SubInfo get activeSub =>
      subs.where((sub) => sub.active).firstOrNull ??
      (subs.isEmpty ? flvpEmptySub : subs.first);

  FlvpTraffic get traffic => _settings.statsScope == FlvpStatsScope.total
      ? FlvpTraffic(
          up: _session.up + flvpHistoryBase.up,
          down: _session.down + flvpHistoryBase.down,
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

  /* ---------- actions ---------- */

  void toggleRunning() {
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
    subs = [for (final sub in subs) sub.copyWith(active: sub.id == id)];
    final target = subs.where((sub) => sub.id == id).firstOrNull;
    notify('已切换到「${target?.name ?? '订阅'}」');
  }

  void importSub(String name, String url) {
    subs = [
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
    final snapshot = List.of(subs);
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
    subs = [for (final sub in subs) sub.copyWith(updated: '刚刚')];
    notify('全部订阅已更新');
  }

  void setSettings(AppSettings Function(AppSettings current) mutate) {
    _settings = mutate(_settings);
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
