import 'package:flutter/material.dart';

import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../icons/flvp_icon.dart';

/// 信息页：把上游的连接 / 请求 / DNS / 日志四类记录聚合到同一个主入口。
///
/// 本批次先搭好 Floway 风格的页面骨架与四标签导航（TODO.md INFO-01 /
/// INFO-02）；列表内容、搜索、详情与标签专属动作接线见 INFO-03 ~ INFO-10。
enum FlvpInfoTab { connections, requests, dns, logs }

class FlvpInfoPage extends StatefulWidget {
  const FlvpInfoPage({super.key});

  @override
  State<FlvpInfoPage> createState() => _FlvpInfoPageState();
}

class _FlvpInfoPageState extends State<FlvpInfoPage> {
  FlvpInfoTab _tab = FlvpInfoTab.connections;

  static const _labels = {
    FlvpInfoTab.connections: '连接',
    FlvpInfoTab.requests: '请求',
    FlvpInfoTab.dns: 'DNS',
    FlvpInfoTab.logs: '日志',
  };

  static const _empty = {
    FlvpInfoTab.connections: '暂无实时连接',
    FlvpInfoTab.requests: '暂无最近请求',
    FlvpInfoTab.dns: '暂无 DNS 查询',
    FlvpInfoTab.logs: '暂无日志记录',
  };

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final tab in FlvpInfoTab.values) Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _overview(colors, tab),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final tab in FlvpInfoTab.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _segment(colors, tab),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              FlvpIcon('Search', size: 15, color: colors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  style: flvpText(13, color: colors.ink),
                  cursorColor: colors.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '搜索${_labels[_tab]}记录',
                    hintStyle: flvpText(13, color: colors.ink3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: Text(
              _empty[_tab]!,
              style: flvpText(13, color: colors.ink3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _overview(FlvpColors colors, FlvpInfoTab tab) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_labels[tab]!, style: flvpText(12, color: colors.ink3)),
          const SizedBox(height: 8),
          Text('—', style: flvpText(18, weight: FontWeight.w600, color: colors.ink)),
        ],
      ),
    );
  }

  Widget _segment(FlvpColors colors, FlvpInfoTab tab) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
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
}