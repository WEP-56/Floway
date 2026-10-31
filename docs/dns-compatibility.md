# Windows 普通代理 DNS 兼容范围

日期：2026-10-30。固定 vp_core v1.1.0 / `fa3e7430371930c440ffb1bdccc6869c63554a34`，补丁 P001/P002。仅实现内核代理连接使用的 resolver，不修改 Windows DNS、路由，不启动 DNS 监听或 TUN。

## 参考依据与取舍

1. vpn-parser `4735038e4148165f3c7af8d3280e04df6d27d3b1` 的 `src/proxy/compiler/vp_core.rs` 复用 Mihomo 编译，再删除部分 DNS policy、添加 223.5.5.5/119.29.29.29、注入 Geo 下载 URL，并过滤或替换部分 Geo 规则。因此它的“能启动”不能作为订阅语义完整保留的证据。这里借鉴按内核编译的边界，不复制这类隐式修改。
2. FlClash `7fd417fb9a9a277c6a9339a8ac87f907df7c25f7` 的 `lib/models/clash_config.dart::Dns/FallbackFilter` 使用 typed 字段表达 default-nameserver、respect-rules、policy、Fake-IP 等语义；这些是其所用内核的能力，不能直接转发给 vp_core。这里只参考字段归属和显式默认值；未复制 FlClash 源码。
3. 固定 vp_core `crates/vp-app/src/lib.rs::assemble` 在 `dns.enable=true` 时构建 resolver，并交给 DIRECT、规则解析与节点拨号；`start_tun_runtime` 才创建 `0.0.0.0:53` listener。因此普通代理可以接入自定义 resolver，无需接管系统 DNS。
4. 固定 `vp-dns/src/lib.rs::parse_server` 会静默跳过不识别的上游，空集合可能回落系统 DNS；部分 DNS 配置字段虽能反序列化却未使用。客户端和宿主均独立严格校验，不仅依赖上游 validate。裸 IP:port 在编译时加 `udp://`，以满足上游配置验证。

## 当前开放子集

DNS 为活动 Profile 的一部分；缺少 `dns` 或仅 `enable: false` 使用系统 resolver。自定义配置需要 `enable: true` 和非空 nameserver，`ipv6` 仅 false，enhanced-mode 仅 redir-host（省略时规范化为此值）。每类上游最多 16 个、禁止重复。

| 字段/格式 | 行为 |
| --- | --- |
| IPv4、IPv4:port、udp://IPv4[:port] | UDP，默认 53 |
| tcp://IPv4[:port] | TCP DNS，默认 53 |
| tls://IPv4[:port] | DoT，默认 853，证书验证开启；P002 限制整体 3 秒 |
| https://host[:port][/path] | DoH，默认 443 /dns-query；证书验证开启；域名上游的 bootstrap 使用系统 DNS |
| fallback | 主上游失败后的备用列表，沿用固定内核语义 |
| fallback-filter | 必须显式 geoip:false；支持 ipcidr 和 `+.域名` 后缀，分别最多 64 条；必须有 fallback |

域名后缀命中时优先走 fallback；主答案命中 CIDR 时尝试 fallback。固定内核在过滤触发但 fallback 失败时仍保留主答案；这里保留其行为，不承诺严格阻断污染地址。多上游答案按固定内核并发查询并集合并，不宣称与 Mihomo 的竞速/过滤策略完全相同。DNS 在规则、全局、直连三种模式均保留；订阅文件中的 DNS 不获得本机监听或系统设置权限。

拒绝：listen、default-nameserver、nameserver-policy、respect-rules、Fake-IP、Geo/geosite 过滤、IPv6 查询、非 DoH 域名上游、#insecure、URL 用户认证/query、未知 scheme 和其他未知字段。关闭 DNS 却携带自定义字段也拒绝，避免忽略字段后报告成功。DoT 不接受域名上游，因为此固定版本的实际解析器仅接受 IP。

## 实现与验证

- [typed DNS 模型](../lib/core/dns_options.dart)、[编译器](../lib/core/compiler.dart)、[宿主独立校验](../native/core-host/src/dns.rs) 与 [P002 来源](../native/vendor/README.md)。原文/规范化 Profile/运行快照仍分开保存，刷新失败保持旧运行状态，节点身份不受 DNS 改动影响。
- [模型测试](../test/dns_options_test.dart)：持久化、三种模式、确定性编译、身份保持、非法/未知语义拒绝和凭据脱敏。
- [真实 Windows runtime](../test/dns_runtime_test.dart)：本地独立 UDP/TCP DNS，节点 bootstrap 与 DIRECT，域名/CIDR 过滤、NXDOMAIN fallback、非法刷新、绕过 Dart 的宿主拒绝、DoT 停滞后 fallback、重启恢复。
- DNS crate 已补跑 4 项公开网络测试：AliDNS DoH/DoT、Tencent DoH、Cloudflare/Google DoH 均通过，保持证书验证。它们验证该 crate 的公开 DNS 查询，不代表整份用户订阅或所有上游均可用；Release host 另通过上述本地转发/回退测试。原始两份真实用户订阅仍有 Fake-IP/Geo/策略等不兼容字段，不能宣称完整导入成功。
