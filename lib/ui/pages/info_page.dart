import 'dart:async';

import 'package:floway/common/common.dart';
import 'package:floway/core/method.dart';
import 'package:floway/enum/enum.dart';
import 'package:floway/features/connection/tracker_speed_ranker.dart';
import 'package:floway/models/models.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/data_display.dart';
import '../widgets/feedback.dart';
import '../widgets/ripple.dart';
import '../widgets/surfaces.dart';

/// 信息页：把上游的连接 / 请求 / DNS / 日志四类真实记录聚合到同一个主入口。
///
/// 数据全部来自上游：连接每秒轮询 `coreHandler.getConnections`，请求 / DNS /
/// 日志直接读 `requestsProvider` / `dnsQueriesProvider` / `logsProvider`。
/// 关闭连接、清除 DNS 缓存、导出日志、日志捕获开关都调用上游原动作
/// （TODO.md INFO-03 ~ INFO-10）。
enum FlvpInfoTab { connections, requests, dns, logs }

class FlvpInfoPage extends ConsumerStatefulWidget {
  const FlvpInfoPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  ConsumerState<FlvpInfoPage> createState() => _FlvpInfoPageState();
}

class _FlvpInfoPageState extends ConsumerState<FlvpInfoPage> {
  FlvpInfoTab _tab = FlvpInfoTab.connections;
  final TextEditingController _query = TextEditingController();
  final ScrollController _listScroll = ScrollController();
  final _ranker = TrackerSpeedRanker();

  Timer? _poll;
  List<TrackerInfo> _connections = const [];
  bool _connLoaded = false;

  LogLevel? _logLevel;

  bool get _pc => widget.platform == FlvpPlatform.pc;

  static const _labels = {
    FlvpInfoTab.connections: '连接',
    FlvpInfoTab.requests: '请求',
    FlvpInfoTab.dns: 'DNS',
    FlvpInfoTab.logs: '日志',
  };

  static const _levelLabels = {
    LogLevel.error: 'ERROR',
    LogLevel.warning: 'WARN',
    LogLevel.info: 'INFO',
    LogLevel.debug: 'DEBUG',
    LogLevel.silent: 'SILENT',
  };

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _query.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (!ref.read(isStartProvider)) {
      if (_connections.isNotEmpty || !_connLoaded) {
        setState(() {
          _connections = const [];
          _connLoaded = true;
        });
      }
      return;
    }
    try {
      final list = await ref.read(coreHandlerProvider).getConnections();
      if (!mounted) return;
      final ranked = _ranker.rank(list, DateTime.now());
      setState(() {
        _connections = ranked;
        _connLoaded = true;
      });
    } catch (error) {
      commonPrint.log(
        'refresh connections error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  void _toast(String message) => FlvpStoreScope.read(context).notify(message);

  Future<void> _closeAllConnections() async {
    try {
      await ref.read(coreHandlerProvider).closeConnections();
      await _refresh();
      if (mounted) _toast('已关闭全部连接');
    } catch (error) {
      if (mounted) {
        _toast('操作失败：${userFacingErrorMessage(error, currentAppLocalizations)}');
      }
    }
  }

  Future<void> _clearDnsCache() async {
    var cleared = false;
    try {
      cleared = await ref.read(coreHandlerProvider).clearDnsCache();
    } catch (error) {
      commonPrint.log(
        'clearDnsCache error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
    if (!mounted) return;
    _toast(cleared ? 'DNS 缓存已清除' : '清除 DNS 缓存失败');
  }

  Future<void> _exportLogs() async {
    try {
      final saved = await globalState.safeRun<bool>(
        () => ref.read(logsProvider.notifier).exportLogs(),
        title: '导出日志',
      );
      if (saved == true && mounted) _toast('日志已导出');
    } catch (error) {
      if (mounted) {
        _toast('导出失败：${userFacingErrorMessage(error, currentAppLocalizations)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final running = ref.watch(isStartProvider);

    final requests = ref.watch(requestsProvider).list;
    final dnsQueries = ref.watch(dnsQueriesProvider).list;
    final logs = ref.watch(logsProvider).list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusRow(colors, running),
        const SizedBox(height: 12),
        _overview(colors, running, requests.length, logs.length),
        const SizedBox(height: 16),
        _tabBar(colors),
        const SizedBox(height: 12),
        _controls(colors),
        const SizedBox(height: 12),
        _body(colors, requests, dnsQueries, logs),
        const SizedBox(height: 10),
        _footer(colors, requests.length, dnsQueries.length, logs.length),
      ],
    );
  }

  // ---------------------------------------------------------------- 概览

  Widget _statusRow(FlvpColors colors, bool running) {
    final tone = running ? colors.ok : colors.ink3;
    return Row(
      children: [
        const Spacer(),
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              Text(
                running ? '运行中' : '未运行',
                style: flvpText(
                  12,
                  weight: FontWeight.w600,
                  color: running ? colors.ok : colors.ink2,
                ),
              ),
            ],
          ),
        ),
        if (running) ...[
          const SizedBox(width: 10),
          Text('实时数据', style: flvpText(12, color: colors.ink3)),
        ],
      ],
    );
  }

  static const _overviewLabels = {
    FlvpInfoTab.connections: '实时连接',
    FlvpInfoTab.requests: '最近请求',
    FlvpInfoTab.logs: '日志记录',
  };

  Widget _overview(
    FlvpColors colors,
    bool running,
    int requestCount,
    int logCount,
  ) {
    Widget card(FlvpInfoTab tab, String value) {
      final active = _tab == tab;
      return _OverviewCard(
        label: _overviewLabels[tab]!,
        value: value,
        active: active,
        colors: colors,
        compact: !_pc,
        onTap: () => setState(() => _tab = tab),
      );
    }

    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: card(
            FlvpInfoTab.connections,
            running ? '${_connections.length}' : '0',
          ),
        ),
        Expanded(child: card(FlvpInfoTab.requests, '$requestCount')),
        Expanded(child: card(FlvpInfoTab.logs, '$logCount')),
      ],
    );
  }

  // ------------------------------------------------------------- 标签与控件

  Widget _tabBar(FlvpColors colors) {
    return Row(
      children: [
        for (final tab in FlvpInfoTab.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _tabChip(colors, tab),
          ),
        const Spacer(),
        if (_tab == FlvpInfoTab.logs) _captureToggle(colors),
      ],
    );
  }

  Widget _tabChip(FlvpColors colors, FlvpInfoTab tab) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() {
        _tab = tab;
        if (_listScroll.hasClients) _listScroll.jumpTo(0);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.14) : colors.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _labels[tab]!,
          style: flvpText(
            13,
            weight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? colors.primary : colors.ink2,
          ),
        ),
      ),
    );
  }

  Widget _captureToggle(FlvpColors colors) {
    final openLogs = ref.watch(
      appSettingProvider.select((state) => state.openLogs),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Text(
          openLogs ? '捕获 · 开启' : '捕获 · 关闭',
          style: flvpText(
            12,
            weight: FontWeight.w500,
            color: openLogs ? colors.ok : colors.ink3,
          ),
        ),
        FlvpSwitch(
          value: openLogs,
          label: '日志捕获',
          onChanged: (value) => ref
              .read(appSettingProvider.notifier)
              .update((state) => state.copyWith(openLogs: value)),
        ),
      ],
    );
  }

  Widget _controls(FlvpColors colors) {
    final search = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surf2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          FlvpIcon('Search', size: 15, color: colors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              style: flvpText(13.5, color: colors.ink),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索${_labels[_tab]}记录',
                hintStyle: flvpText(13.5, color: colors.ink3),
              ),
            ),
          ),
          if (_query.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _query.clear();
                setState(() {});
              },
              child: FlvpIcon('X', size: 15, color: colors.ink3),
            ),
        ],
      ),
    );

    final chips = _tab == FlvpInfoTab.logs
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(colors, '全部', _logLevel == null, () {
                setState(() => _logLevel = null);
              }),
              for (final level in const [
                LogLevel.error,
                LogLevel.warning,
                LogLevel.info,
                LogLevel.debug,
              ])
                _filterChip(
                  colors,
                  _levelLabels[level]!,
                  _logLevel == level,
                  () => setState(() => _logLevel = level),
                ),
            ],
          )
        : null;

    if (chips == null) return search;
    if (_pc) {
      return Row(
        children: [SizedBox(width: 320, child: search), const SizedBox(width: 16), Expanded(child: chips)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [search, chips],
    );
  }

  Widget _filterChip(
    FlvpColors colors,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FlvpMotion.control,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surf2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: flvpText(
            12.5,
            color: selected ? colors.onprimary : colors.ink2,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 列表

  Widget _body(
    FlvpColors colors,
    List<TrackerInfo> requests,
    List<DnsQuery> dnsQueries,
    List<Log> logs,
  ) {
    final keyword = _query.text.trim().toLowerCase();

    final List<Widget> rows;
    var emptyText = '';
    switch (_tab) {
      case FlvpInfoTab.connections:
        final list = [
          for (final info in _connections)
            if (_trackerMatches(info, keyword))
              _trackerRow(colors, info, live: true),
        ];
        rows = list;
        emptyText = '暂无实时连接';
      case FlvpInfoTab.requests:
        final list = [
          for (final info in requests.reversed)
            if (_trackerMatches(info, keyword))
              _trackerRow(colors, info, live: false),
        ];
        rows = list;
        emptyText = '暂无最近请求';
      case FlvpInfoTab.dns:
        final list = [
          for (final query in dnsQueries.reversed)
            if (_dnsMatches(query, keyword)) _dnsRow(colors, query),
        ];
        rows = list;
        emptyText = '暂无 DNS 查询';
      case FlvpInfoTab.logs:
        final list = [
          for (final log in logs.reversed)
            if (_logMatches(log, keyword)) _logRow(colors, log),
        ];
        rows = list;
        emptyText = '暂无日志记录';
    }

    final Widget content;
    if (rows.isEmpty) {
      final loading = _tab == FlvpInfoTab.connections &&
          ref.read(isStartProvider) &&
          !_connLoaded;
      content = SizedBox(
        height: _pc ? 260 : 220,
        child: Center(
          child: loading
              ? FlvpSpinner(size: 20, color: colors.ink3)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    FlvpIcon('Activity', size: 26, color: colors.ink3),
                    Text(
                      emptyText,
                      style: flvpText(
                        13.5,
                        weight: FontWeight.w400,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ),
        ),
      );
    } else {
      content = Container(
        height: _pc ? 520 : 440,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: FlvpElevation.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: FlvpThinScrollbar(
          controller: _listScroll,
          child: ListView.separated(
            controller: _listScroll,
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: colors.hair.withValues(alpha: 0.6),
            ),
            itemBuilder: (_, index) => rows[index],
          ),
        ),
      );
    }
    return content;
  }

  bool _trackerMatches(TrackerInfo info, String keyword) {
    if (keyword.isEmpty) return true;
    return info.searchFields.any((f) => f.toLowerCase().contains(keyword));
  }

  bool _dnsMatches(DnsQuery query, String keyword) {
    if (keyword.isEmpty) return true;
    return query.searchFields.any((f) => f.toLowerCase().contains(keyword));
  }

  bool _logMatches(Log log, String keyword) {
    if (_logLevel != null && log.logLevel != _logLevel) return false;
    if (keyword.isEmpty) return true;
    final payload = LogPayload.parse(log.payload);
    return log.payload.toLowerCase().contains(keyword) ||
        payload.message.toLowerCase().contains(keyword) ||
        log.logLevel.name.toLowerCase().contains(keyword);
  }

  Widget _trackerRow(FlvpColors colors, TrackerInfo info, {required bool live}) {
    final meta = info.metadata;
    final network = meta.network.isEmpty ? 'TCP' : meta.network.toUpperCase();
    final target = meta.destinationPort.isEmpty
        ? info.title
        : '${info.title}:${meta.destinationPort}';
    final rule = info.rulePayload.isEmpty
        ? info.rule
        : '${info.rule}(${info.rulePayload})';
    final exit = info.chains.isEmpty ? '' : info.chains.first;

    return _RecordRow(
      colors: colors,
      onTap: () => _showTrackerDetail(info, live ? '连接详情' : '请求详情'),
      header: [
        _Tag(label: network, color: colors.ink2),
        _Muted(
          live
              ? _elapsed(DateTime.now().difference(info.start))
              : info.start.showFull,
        ),
        if (live) ...[
          _Muted('↑ ${(info.uploadSpeed ?? 0).traffic.show}/s'),
          _Muted('↓ ${(info.downloadSpeed ?? 0).traffic.show}/s'),
        ],
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            target,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: flvpText(13.5, color: colors.ink),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (rule.isNotEmpty)
                _Muted(rule, maxWidth: 240),
              if (exit.isNotEmpty) _Tag(label: exit, color: colors.primary),
              if (info.progressText.isNotEmpty) _Muted(info.progressText, maxWidth: 200),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dnsRow(FlvpColors colors, DnsQuery query) {
    final failed = query.isFailed;
    return _RecordRow(
      colors: colors,
      onTap: () => _showDnsDetail(query),
      header: [
        _Tag(label: query.type, color: colors.ink2),
        _Muted(query.time.showFull),
        if (query.initiator != null) _Muted(query.initiator!.label),
        _Muted('${query.delay} ms'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            query.domain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: flvpText(13.5, color: colors.ink),
          ),
          if (query.summary.isNotEmpty)
            Text(
              query.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: flvpText(
                12.5,
                weight: FontWeight.w400,
                color: failed ? colors.err : colors.ink2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _logRow(FlvpColors colors, Log log) {
    final tone = switch (log.logLevel) {
      LogLevel.error => colors.err,
      LogLevel.warning => colors.warn,
      _ => colors.ink2,
    };
    final payload = LogPayload.parse(log.payload);
    final route = payload.route;
    return _RecordRow(
      colors: colors,
      onTap: () => _showLogDetail(log, payload),
      header: [
        _Tag(label: _levelLabels[log.logLevel]!, color: tone, filled: true),
        _Muted(_logTime(log.dateTime)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          if (route != null) ...[
            Text(
              route.destination,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: flvpText(13.5, color: colors.ink),
            ),
            if (route.error.isNotEmpty)
              Text(
                route.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: flvpText(12.5, weight: FontWeight.w400, color: colors.err),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (route.rule.isNotEmpty) _Muted(route.rule, maxWidth: 220),
                _Tag(label: route.proxy, color: colors.primary),
              ],
            ),
          ] else
            Text(
              payload.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: flvpText(13, weight: FontWeight.w400, color: colors.ink),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 页脚

  Widget _footer(FlvpColors colors, int requestCount, int dnsCount, int logCount) {
    final hint = switch (_tab) {
      FlvpInfoTab.connections => '当前 ${_connections.length} 条连接 · 每秒刷新',
      FlvpInfoTab.requests => '保留最近 $requestCount 条请求 · 最新在上',
      FlvpInfoTab.dns => '共 $dnsCount 条 DNS 查询 · 最新在上',
      FlvpInfoTab.logs => '共 $logCount 条日志 · 最新在上',
    };
    final actions = <Widget>[
      if (_tab == FlvpInfoTab.connections)
        FlvpButton(
          variant: FlvpButtonVariant.danger,
          size: FlvpControlSize.sm,
          label: '关闭全部',
          onPressed: _connections.isEmpty ? null : _closeAllConnections,
        ),
      if (_tab == FlvpInfoTab.dns)
        FlvpButton(
          variant: FlvpButtonVariant.tonal,
          size: FlvpControlSize.sm,
          label: '清除缓存',
          onPressed: _clearDnsCache,
        ),
      if (_tab == FlvpInfoTab.logs)
        FlvpButton(
          variant: FlvpButtonVariant.tonal,
          size: FlvpControlSize.sm,
          label: '导出',
          onPressed: _exportLogs,
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: Text(
            hint,
            style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 12),
          for (final action in actions) action,
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 详情

  void _showSheet(String title, Widget child) {
    final host = FlvpModalHost.of(context);
    host.show(
      (context) => FlvpModal(
        platform: widget.platform,
        title: title,
        onClose: host.close,
        child: child,
      ),
    );
  }

  void _showTrackerDetail(TrackerInfo info, String title) {
    final meta = info.metadata;
    final rule = info.rulePayload.isEmpty
        ? info.rule
        : '${info.rule}(${info.rulePayload})';
    _showSheet(
      title,
      _DetailView(
        sections: [
          (
            '基本信息',
            <(String, String)>[
              ('创建时间', info.start.showFull),
              ('网络类型', meta.network),
              ('进程', info.progressText),
              ('规则', rule),
              ('上传', info.upload.traffic.show),
              ('下载', info.download.traffic.show),
            ],
          ),
          (
            '地址',
            <(String, String)>[
              ('主机', meta.host),
              ('来源', _endpoint(meta.sourceIP, meta.sourcePort)),
              ('目标', _endpoint(meta.destinationIP, meta.destinationPort)),
              ('目标 GeoIP', meta.destinationGeoIP.join(' ')),
              ('目标 ASN', meta.destinationIPASN),
              ('远端地址', meta.remoteDestination),
            ],
          ),
          (
            '代理',
            <(String, String)>[
              ('特殊代理', meta.specialProxy),
              ('特殊规则', meta.specialRules),
              ('DNS 模式', meta.dnsMode?.name ?? ''),
              ('代理链', info.chains.reversed.join(' → ')),
            ],
          ),
        ],
        colors: FlvpThemeScope.colorsOf(context),
        onCopy: _copy,
      ),
    );
  }

  void _showDnsDetail(DnsQuery query) {
    _showSheet(
      'DNS 详情',
      _DetailView(
        sections: [
          (
            '基本信息',
            <(String, String)>[
              ('时间', query.time.showFull),
              ('域名', query.domain),
              ('记录类型', query.type),
              ('发起方', query.initiator?.label ?? ''),
              ('来源', query.upstream),
              ('缓存', query.cached ? '是' : '否'),
              ('响应码', query.rcode),
              ('延迟', '${query.delay} ms'),
            ],
          ),
          if (query.error.isNotEmpty) ('错误', <(String, String)>[('', query.error)]),
          if (query.answers.isNotEmpty)
            (
              '答案',
              <(String, String)>[for (final answer in query.answers) ('', answer)],
            ),
        ],
        colors: FlvpThemeScope.colorsOf(context),
        onCopy: _copy,
      ),
    );
  }

  void _showLogDetail(Log log, LogPayload payload) {
    final route = payload.route;
    _showSheet(
      '日志详情',
      _DetailView(
        sections: [
          (
            '基本信息',
            <(String, String)>[
              ('时间', log.dateTime),
              ('等级', _levelLabels[log.logLevel]!),
              ('标签', payload.tag),
              ('内容', payload.message),
            ],
          ),
          if (route != null)
            (
              '路由',
              <(String, String)>[
                ('目标', route.destination),
                ('规则', route.rule),
                ('出口', route.proxy),
                ('来源', route.source),
                ('详情', route.sourceDetail),
                ('错误', route.error),
              ],
            ),
        ],
        colors: FlvpThemeScope.colorsOf(context),
        onCopy: _copy,
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('已复制');
  }
}

String _endpoint(String ip, String port) {
  if (ip.isEmpty) return '';
  return port.isEmpty ? ip : '$ip:$port';
}

String _elapsed(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  return '${(minutes / 60).toStringAsFixed(1)} h';
}

String _logTime(String dateTime) {
  final parts = dateTime.split(' ');
  return parts.length > 1 ? parts.last : dateTime;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.active,
    required this.colors,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final FlvpColors colors;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FlvpCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 12 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            style: flvpText(
              compact ? 22 : 26,
              height: 1.1,
              color: active ? colors.primary : colors.ink,
              tabular: true,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: flvpText(12, color: colors.ink3)),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.colors,
    required this.header,
    required this.child,
    required this.onTap,
  });

  final FlvpColors colors;
  final List<Widget> header;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FlvpHover(
      builder: (context, hovered) => FlvpRipple(
        color: colors.ink,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: FlvpMotion.hover,
            color: hovered ? colors.inkHover() : const Color(0x00000000),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    for (final item in header) Flexible(child: item),
                  ],
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.color,
    this.filled = false,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.14)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: flvpText(11, weight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text, {this.maxWidth});

  final String text;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final widget = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: flvpText(11.5, weight: FontWeight.w400, color: colors.ink3, tabular: true),
    );
    if (maxWidth == null) return widget;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: widget,
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.sections,
    required this.colors,
    required this.onCopy,
  });

  final List<(String, List<(String, String)>)> sections;
  final FlvpColors colors;
  final Future<void> Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final built = <Widget>[];
    for (final (title, rows) in sections) {
      final visible = [
        for (final (label, value) in rows)
          if (value.isNotEmpty) (label, value),
      ];
      if (visible.isEmpty) continue;
      built.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 2),
                child: Text(
                  title,
                  style: flvpText(
                    12.5,
                    weight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colors.surf2,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    for (final (label, value) in visible)
                      InkWell(
                        onTap: () => onCopy(value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (label.isNotEmpty) ...[
                                SizedBox(
                                  width: 84,
                                  child: Text(
                                    label,
                                    style: flvpText(
                                      12.5,
                                      weight: FontWeight.w400,
                                      color: colors.ink3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: SelectableText(
                                  value,
                                  style: flvpText(
                                    13,
                                    weight: FontWeight.w400,
                                    color: colors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: built,
    );
  }
}
