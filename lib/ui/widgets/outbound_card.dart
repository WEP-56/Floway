import 'package:floway/common/service_probe.dart' show routedOutbound;
import 'package:floway/enum/enum.dart';
import 'package:floway/models/ip_quality.dart';
import 'package:floway/providers/ip_quality.dart';
import 'package:floway/providers/outbound_ip.dart';
import 'package:floway/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/motion.dart';
import '../design/theme_scope.dart';
import '../icons/flvp_icon.dart';
import '../widgets/ripple.dart';
import '../widgets/surfaces.dart';

/// 出口信息卡片：出口 IP、地区、IP 质量与所属组织，数据来自上游探针。
class FlvpOutboundCard extends ConsumerStatefulWidget {
  const FlvpOutboundCard({super.key});

  @override
  ConsumerState<FlvpOutboundCard> createState() => _FlvpOutboundCardState();
}

class _FlvpOutboundCardState extends ConsumerState<FlvpOutboundCard> {
  late final _probe = ref.read(outboundIpProbeProvider.notifier);

  @override
  void initState() {
    super.initState();
    _probe.watch(routedOutbound);
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  void _refresh() {
    _probe.refresh(const [routedOutbound]);
    final ip = ref.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip;
    if (ip != null && ref.read(ipQualityProvider(ip)).hasError) {
      ref.invalidate(ipQualityProvider(ip));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final info = entry.value;
    final qualityState = info == null
        ? null
        : ref.watch(ipQualityProvider(info.ip));
    final quality = qualityState?.value;
    final loading =
        entry.phase == ProbePhase.probing ||
        (qualityState != null && qualityState.isLoading);

    final cells = <Widget>[
      _Cell(
        label: '出口 IP',
        value: info?.ip ?? '—',
        loading: info == null && loading,
      ),
      _Cell(
        label: '地区',
        value: info == null ? '—' : _regionLabel(info.countryCode),
        loading: info == null && loading,
      ),
      _Cell(
        label: 'IP 质量',
        value: quality == null
            ? '—'
            : '${_levelLabel(quality.level)} · ${_typeLabel(quality.type)}',
        tone: switch (quality?.level) {
          IpQualityLevel.good => colors.ok,
          IpQualityLevel.normal => colors.ink2,
          IpQualityLevel.risky => colors.warn,
          null => null,
        },
        loading: quality == null && loading,
      ),
      _Cell(
        label: '组织',
        value: (quality?.organization?.isNotEmpty ?? false)
            ? quality!.organization!
            : '—',
        loading: quality == null && loading,
      ),
    ];

    return FlvpCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final (index, cell) in cells.indexed) ...[
            if (index > 0) const SizedBox(width: 20),
            Expanded(child: cell),
          ],
          const SizedBox(width: 8),
          FlvpHover(
            builder: (context, hovered) => FlvpRipple(
              color: colors.ink,
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: _refresh,
                child: AnimatedContainer(
                  duration: FlvpMotion.hover,
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hovered ? colors.surf3 : colors.surf2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: loading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.ink3,
                          ),
                        )
                      : FlvpIcon('RefreshCw', size: 15, color: colors.ink2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    this.tone,
    this.loading = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: flvpText(11.5, color: colors.ink3)),
        const SizedBox(height: 4),
        Text(
          loading ? '查询中…' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: flvpText(13.5, color: tone ?? colors.ink, tabular: true),
        ),
      ],
    );
  }
}

String _levelLabel(IpQualityLevel level) => switch (level) {
  IpQualityLevel.good => '优质',
  IpQualityLevel.normal => '普通',
  IpQualityLevel.risky => '风险',
};

String _typeLabel(IpType type) => switch (type) {
  IpType.residential => '住宅',
  IpType.mobile => '移动',
  IpType.business => '商业',
  IpType.hosting => '机房',
};

/// 常见出口地区的显示名；Windows 没有国旗 emoji 字体，直接用地区名。
const _regionNames = {
  'CN': '中国',
  'HK': '香港',
  'TW': '台湾',
  'MO': '澳门',
  'SG': '新加坡',
  'JP': '日本',
  'KR': '韩国',
  'US': '美国',
  'GB': '英国',
  'DE': '德国',
  'FR': '法国',
  'NL': '荷兰',
  'CA': '加拿大',
  'AU': '澳大利亚',
  'RU': '俄罗斯',
  'IN': '印度',
  'TR': '土耳其',
  'BR': '巴西',
  'MY': '马来西亚',
  'TH': '泰国',
  'VN': '越南',
  'PH': '菲律宾',
  'ID': '印度尼西亚',
};

String _regionLabel(String code) {
  final upper = code.toUpperCase();
  return _regionNames[upper] ?? upper;
}
