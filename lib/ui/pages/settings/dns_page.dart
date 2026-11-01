import 'package:floway/views/config/dns.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/feedback.dart';
import 'override_page.dart';

/// DNS 设置：沿用上游 `DnsView` 的覆写规格（字段、校验、生效方式不变），
/// 只把呈现换成 Floway 的分组卡片与行。
class FlvpDnsPage extends StatelessWidget {
  const FlvpDnsPage({super.key, required this.platform});

  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) => FlvpOverridePage(
    spec: const DnsView().spec,
    platform: platform,
    subtitle: '未添加的项沿用配置本身的值',
  );
}
