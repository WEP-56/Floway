import 'package:floway/views/config/dns.dart';
import 'package:floway/views/config/ntp.dart';
import 'package:floway/views/config/sniffer.dart';
import 'package:floway/views/config/tun.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/feedback.dart';
import '../settings/override_page.dart';

/// 单份配置的 DNS 覆写：沿用上游 `DnsView.profile` 的覆写规格，呈现走
/// Floway 的覆写页。
class FlvpProfileDnsPage extends StatelessWidget {
  const FlvpProfileDnsPage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) => FlvpOverridePage(
    spec: DnsView.profile(profileId).spec,
    platform: platform,
    subtitle: '这份配置自己的 DNS 设置',
  );
}

/// 单份配置的 NTP 覆写。
class FlvpProfileNtpPage extends StatelessWidget {
  const FlvpProfileNtpPage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) => FlvpOverridePage(
    spec: NtpView(profileId).spec,
    platform: platform,
    subtitle: '这份配置自己的 NTP 设置',
  );
}

/// 单份配置的域名嗅探覆写。
class FlvpProfileSnifferPage extends StatelessWidget {
  const FlvpProfileSnifferPage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) => FlvpOverridePage(
    spec: SnifferView(profileId).spec,
    platform: platform,
    subtitle: '这份配置自己的嗅探设置',
  );
}

/// 单份配置的 TUN 覆写。
class FlvpProfileTunPage extends StatelessWidget {
  const FlvpProfileTunPage({
    super.key,
    required this.profileId,
    required this.platform,
  });

  final int profileId;
  final FlvpPlatform platform;

  @override
  Widget build(BuildContext context) => FlvpOverridePage(
    spec: TunView(profileId).spec,
    platform: platform,
    subtitle: '这份配置自己的 TUN 设置',
  );
}
