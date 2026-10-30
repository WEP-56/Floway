# vp_core 调研与接入基线

## 1. 版本与证据范围

2026-10-30 在线查询 GitHub 仓库、main HEAD 和最新 Release，并与本地 Git 核对：

| 项目 | 固定基线 |
| --- | --- |
| vp_core 本地目录 | `core-example/vp_core` |
| 上游 | <https://github.com/mateo-ki/vp_core> |
| main / 本地 HEAD / v1.1.0 tag | `fa3e7430371930c440ffb1bdccc6869c63554a34` |
| 提交时间 | 2026-10-30 08:31:33 +08:00 |
| 最新发布 | v1.1.0，2026-10-30 08:40:04 +08:00 |
| FlClash 参考目录 | `cilent-example/FlClash`（保留现有目录拼写） |
| FlClash 固定提交 | `7fd417fb9a9a277c6a9339a8ac87f907df7c25f7`，v0.9.2 |

以下结论只适用于此提交。升级时必须重新核对配置 schema、API、FFI、规则降级、TUN 和后台任务。README 的“全协议、全平台、工业级稳定”是上游描述，不能作为 FLVPcore 的验收结论；本轮没有验证吞吐、内存或所有协议互通。

Release 已发布 Windows x86_64 MSVC CLI 包，包含 Wintun；Android 包构建 arm64-v8a、armeabi-v7a、x86_64 的 `libvpcore.so` 与 C 头文件。**C ABI 库并不等于现成 JNI 插件**。Windows ARM64 没有对应的本次官方二进制，暂不列入首发支持。

可核对的发布摘要：

| 产物 | SHA-256（GitHub Release asset digest） |
| --- | --- |
| `vpcore-v1.1.0-x86_64-pc-windows-msvc.zip` | `29f03d83bbef8407a50f8493f0794950d41167d7a585cf41a3bb70d0879cb017` |
| `vpcore-android-ffi.tar.gz` | `1011e09e117a7371e8b1eadfb4e74c6934c61ef6e993a7c50636df46ee353325` |

此处只核实发布元数据，未下载并验证这两个包。生产发行需自行下载核验、保存构建来源与补丁摘要，不能只相信文件名或版本号。

## 2. 源码索引

下文以编号引用。链接固定到提交，可用于审查；本地参考目录被根 `.gitignore` 忽略，协作者应按固定提交自行获取。

| 编号 | 源码与主要依据 |
| --- | --- |
| S1 | [vp-config/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-config/src/lib.rs)：YAML / JSON5、按扩展名选择格式、parse_and_validate |
| S2 | [vp-config/model.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-config/src/model.rs)：真实字段、别名、默认值、协议枚举 |
| S3 | [vp-config/validate.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-config/src/validate.rs)：校验只覆盖部分命名、引用、端口、DNS 等 |
| S4 | [vp-app/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-app/src/lib.rs)：assemble、reload_with_text、sync_tun_state、provider、Geo 资源 |
| S5 | [vp-app/api.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-app/src/api.rs)：控制 API、鉴权、请求限制、流量 WS |
| S6 | [vp-ffi/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-ffi/src/lib.rs) 与 [vpcore.h](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-ffi/include/vpcore.h)：实际 ABI、全局单例、FD 与错误 |
| S7 | [vp-rule/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-rule/src/lib.rs)：规则编译、NeverMatch、no-resolve、逻辑规则 |
| S8 | [vp-rule/provider.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-rule/src/provider.rs)：文本 / payload YAML、classical 子集 |
| S9 | [vp-router/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-router/src/lib.rs)：global_outbound、首命中、DNS、未命中回退 |
| S10 | [vp-tun/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-tun/src/lib.rs)：from_raw_fd、tokio::fs、独立 FakeIP 池与系统 resolver |
| S11 | [auto_route.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-tun/src/auto_route.rs)：只添加指定网段、广域清理 /1 路由 |
| S12 | [vp-bin/main.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-bin/src/main.rs)：managed-stdin、mtime 自动重载、退出清理、validate |
| S13 | [vp-transport/lib.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-transport/src/lib.rs)：TCP 拨号；QUIC、UDP 还分散于各协议实现 |
| S14 | [release.yml](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/.github/workflows/release.yml)：平台、ABI、打包与 Wintun |
| S15 | [vp-protocol/sub.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-protocol/src/sub.rs)：分享链接、订阅和 provider 解析 |
| S16 | [vp-core/process.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-core/src/process.rs)、[session.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-core/src/session.rs)、[vp-rule/process.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-rule/src/process.rs)、[inbound/dispatch.rs](https://github.com/mateo-ki/vp_core/blob/fa3e7430371930c440ffb1bdccc6869c63554a34/crates/vp-protocol/src/inbound/dispatch.rs)：进程信息来源与平台限制 |

## 3. 能力矩阵：解析、装配、可用必须分开

| 主题 | 已核实 | 对 FLVPcore 的影响 |
| --- | --- | --- |
| 配置 | Clash 风格 YAML 与同构 JSON/JSON5；无完整 mihomo 兼容保证 | 自建版本化模型、严格兼容诊断，禁止直接透传订阅配置 |
| 静态校验 | 不装配 provider、Geo、完整规则，不检测实际端口占用 | `validate` 成功只算第一层通过 |
| 未知字段 | 多数结构未启用 deny_unknown_fields | “不报错”可能是字段被忽略，导入要输出兼容报告 |
| 规则 | 有域名、IP、Geo、ASN、逻辑、子规则、规则集等实现 | 需严格预检，未知规则会告警后变成永不命中 |
| 资源 | 支持在线拉取和缓存降级；Geo 缺失时规则可被跳过 | 客户端统一下载并固定本地快照，默认禁止缺资源继续应用 |
| 监听 | 普通入站和 TUN 失败有路径只记 warn | 进程存在、API 可访问或 vp_start=0 都不能证明代理就绪 |
| 控制器 | 部分 Clash 风格 REST | 自建适配层，不能直接接完整 mihomo SDK |
| 热重载 | 重建 Router；普通监听、控制器、认证不重建；TUN 只同步开关 | 用变更分类表决定 reload 或 restart |
| 全局出站 | 从 HashMap values 选首个组 / 节点 | 多组时不能保证选中预期组；需明确全局组补丁或统一规则模式编译 |
| Windows TUN | Wintun 设备路径、路由守卫存在 | 尚无完整系统接管、节点绕行和精确恢复证明 |
| Android TUN | C ABI 能传 FD，Unix 分支 from_raw_fd 接管 | 缺 protect、完整就绪状态和明确失败时 FD 契约 |
| 移动端 DNS | 设备读取、外部 DNS server 和不同 FakeIP 池间存在割裂 | 必须先修复并真机验证再宣布 VPN 可用 |

### 3.1 协议、传输与导入能力必须分别标记

S2 的 ProxyKind 与 `vp-protocol/src/lib.rs` 出站装配包括 `ss`、`ssr`、`vmess`、`vless`、`trojan`、`snell`、`anytls`、`ssh`、`brook`、`mieru`、`naive`、`socks5`、`http`、`https`、`hysteria`、`hysteria2`、`tuic`、`wireguard`、`direct`、`reject`。这是源码可配置集合，**不是本轮通过真机互通的协议列表**。

| 维度 | 当前边界 | 客户端约束 |
| --- | --- | --- |
| UDP | 多协议依赖 udp 开关；SSH、Mieru、HTTP/HTTPS 等没有相同的 UDP 能力 | 按具体节点/组能力显示，不因内核支持 QUIC 就把所有节点标为 UDP |
| 分享链接 | S15 的 parse_uri 有 VLESS/VMess/Trojan/SS/SSR、Anytls、SSH、Brook、Mieru、Snell、Hysteria 1、Naive 等分支，但没有对应 Hysteria2/TUIC/WireGuard URI 分支 | 配置可用与 URI 可导入分开；需独立补充转换并验证，不能静默丢链接 |
| 普通传输配置 | transport_of_full 接受 tcp/ws/grpc/http；其他 network 值返回 Unsupported | 不把仓库有 quic.rs 推断成任意节点都支持 network: quic |
| 插件 | SS 对未支持 plugin 有告警后忽略路径 | 不支持的插件必须阻止应用，否则会改变握手语义 |
| 惰性装配 | LazyOutbound 在首用时才构建真实协议，且缓存构建结果/错误 | 配置校验、App 装配成功仍可能在首连才发现协议参数错误；preflight 应主动校验选定出站 |
| 服务端入站 | 有多种 listener 构建，但这不是客户端首期目标 | v1 不从订阅激活服务端 listeners、证书路径、redir/tproxy 等本机入口 |

DNS 同样要区分字段与行为：S2 存在 `dns.listen`、`default-nameserver`、`enhanced-mode`、`dns.ipv6` 等字段，但 S4 不能证明这些都按 mihomo 语义执行；TUN 路径有固定端口及独立池。v1 仅开放经过配置到数据面的完整验证字段，不按示例 YAML 的字段数量制作功能清单。

## 4. 必须优先解决的缺口

| ID / 优先级 | 依据与问题 | 最小完成条件 |
| --- | --- | --- |
| C01 / P0 | S6/S13：无 socket protect 注册接口，TCP/UDP/QUIC/DNS 建 socket 路径分散 | Android 所有外连 socket 在 connect/首发前 protect，覆盖重连与测速 |
| C02 / P0 | S4：TUN 或 mixed 监听失败可能仍返回启动成功 | 宿主提供结构化就绪回执；必需入站失败整体回滚 |
| C03 / P0 | S10：外部 FD 用 tokio::fs::File；缺少明确的包边界、取消、EAGAIN 行为契约 | Android 采用专门 FD I/O，验证阻塞/非阻塞、停机唤醒、一次一个 IP 包和短写 |
| C04 / P0 | S4/S10：外部 DNS server 绑定 0.0.0.0:53；TUN 内另建 FakeIP 池和 Resolver::system | Android 不依赖本地 53 监听；DNS 劫持共享配置 resolver 与 FakeIP 映射，A/AAAA、TCP/UDP 53 均有策略 |
| C05 / P0 | S11/S12：auto-route 只有指定网段；clean_all_routes 按目的网段删除 /1，CLI 正常退出也调用 | Windows 宿主拥有完整路由事务与精确恢复；禁止日常调用该广域清理路径 |
| C06 / P0 | S6：FD 接管前后可能报错或只 warn；vp_stop 无完整资源关闭回执 | 明确 ownershipAccepted，并实现显式 App shutdown 与句柄回收检查 |
| C07 / P1 | S4：provider 定时任务不都归 Router 管理，可能持旧 rules_spec；重载时全局 resolver/tuning 在成功提交前已有副作用 | 下载归客户端唯一所有；无 URL/interval 自动任务；重载准备无副作用或可回滚 |
| C08 / P1 | S5：/traffic Accept 固定 vpcore，非标准 WS；无 PATCH /configs、日志、memory、规则 provider API；dns/flush 只回成功 | 先轮询 /connections；所需 API 独立实现并加协议测试 |
| C09 / P1 | S9：global 和未命中路径依赖 HashMap 枚举；日志“回落 DIRECT”与实际 global_outbound 不一致 | 总是生成显式 MATCH；全局选择确定化 |
| C10 / P1 | S6：FFI 从进程 cwd 取资源根，reload 沿用启动 fmt；错误为进程级全局槽 | 桥接支持显式 dataRoot/格式、串行命令、每请求独立错误 |

P0 是对应功能发布的阻塞项。可以先做普通代理原型，但不能将 Android FD 注入或 Windows 建立虚拟网卡视为 VPN 接入完成。

## 5. FlClash 的价值与边界

固定参考：[FlClash v0.9.2 提交](https://github.com/chen08209/FlClash/tree/7fd417fb9a9a277c6a9339a8ac87f907df7c25f7)。此本地版本比简单的“Flutter + mihomo”还多了桌面 Rust helper、IPC 与生命周期治理，值得借鉴责任拆分。

| 参考位置（相对 FlClash 根） | 可借鉴 | 不能直接套用 |
| --- | --- | --- |
| `lib/core/desktop/lifecycle.dart` | desired intent、revision、进程 lease、断线代际 | 自有 RPC/握手不是 vp_core REST |
| `lib/core/desktop/launcher.dart`、`helper_client.dart` | 普通启动与提权启动分离 | 当前 core 参数、stop 行为与 vp_core 不同 |
| `services/helper/src/service/windows.rs`、`peer.rs`、`owner.rs` | SCM 服务、用户 SID、受限进程所有权 | 需要按本项目能力重新实现，不能开放任意命令执行 |
| `android/.../ServiceStateMachine.kt` | 最新用户意图仲裁、权限回调防竞态 | 状态与 mihomo 封装绑定 |
| `android/service/.../VpnService.kt`、`android/core/.../Core.kt` | protect、FD、UID/package、Builder 与撤销回调 | Go Mobile/JNI、tun handler 不存在于 vp_core |
| `android/service/.../NetworkObserver.kt` | 观察非 VPN 底层网络、DNS 变动去抖 | `resetNetwork/updateDns` 不是 vp_core API |
| `lib/database/`、`lib/common/task.dart` | profile/规则/选择状态分层，任务编排 | mihomo 配置覆盖规则及数据库不应成为本项目协议 |

本地 FlClash LICENSE 为 GPL-3.0；vp_core Cargo/README 标称 MIT，但本地仓库根未见 LICENSE 正文。若 FLVPcore 保持 MIT，优先独立实现上述架构思想；复制或改写 FlClash 代码前必须确定授权兼容及再分发义务，并补齐上游许可文本与依赖清单。这会直接影响代码复用方式。

## 6. 实施次序与稳定门槛

1. **共同底座**：配置/规则模型、编译器、快照、能力清单、事务日志；相同输入必须产生相同跨端业务配置摘要。
2. **普通代理纵切**：Windows 子进程或自建宿主；Android JNI 普通 mixed；本地 SOCKS/HTTP 请求、选择节点、重载回滚。
3. **平台接管**：Windows 特权宿主与路由；Android protect、FD、DNS、原生后台所有权。先各自闭环，不把设备接管埋进 Dart 配置代码。
4. **稳定阶段**：双端 24 小时持续连接、至少 100 次启停/配置更新、网络变动、撤权、宿主崩溃、升级失败恢复；具体设备矩阵见两端文档。
5. **扩展平台**：上述门槛及完整功能验收通过后再立项 macOS、Linux、iOS。当前不为这些平台编写未经验证的接入承诺。

## 7. 官方平台依据

2026-10-30 实际访问以下官方页面（HTTP 200）；平台实现时按所选 targetSdk / Windows 最低版本重新检查：

- [Android VPN 开发](https://developer.android.com/develop/connectivity/vpn)：prepare、protect、前台服务、always-on、按应用 VPN。
- [VpnService](https://developer.android.com/reference/android/net/VpnService) 与 [Builder](https://developer.android.com/reference/android/net/VpnService.Builder)：FD、路由、setBlocking、allowFamily、应用白/黑名单。
- [前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types) 与 [后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)：Android 14+ 类型、权限、VPN systemExempted 的适用条件。
- [Android 16 KB 页支持](https://developer.android.com/guide/practices/page-sizes)：原生库和打包适配。
- [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)、[Named Pipe 访问控制](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)、[InternetSetOptionW](https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-internetsetoptionw)。
- [Wintun 官方站点](https://www.wintun.net/)：架构、发行与驱动来源。
