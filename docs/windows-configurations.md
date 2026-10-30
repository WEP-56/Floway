# Windows 配置与订阅仓库增量

日期：2026-10-30。按用户最新要求，当前只推进 Windows，不实施旧数据迁移，也未构建/验收 Android。

## 已实现

- 仪表盘系统代理右侧新增同尺寸、同样式的 TUN 开关。当前 `tunMode` 仍不具备原生能力，点击提示尚未实现并保持关闭；不宣称整机 VPN 可用。
- 配置来源分为远程订阅、本地文件快照、手动单节点。来源 UUID 独立于 Profile ID 与节点显示名称；节点页只使用活动配置的节点和内置 DIRECT。
- 每份来源保存原文、SHA-256、规范化 Profile、选择与更新时间。原始文件在导入后无需保留；远程 URL 仅存私有应用状态，UI 仅显示主机名，复制链接动作使用系统剪贴板。
- 导入弹窗复用现有字段、分段按钮、弹窗与按钮。真实剪贴板粘贴、Windows 系统文件选择器及手动 HTTP/SOCKS5 创建均已接线，失败不关闭弹窗或显示成功。
- 活动配置和库共同存入 `state/client.json`，运行快照携带同一份库；更新/切换先解析、校验、编译和 staging，再应用宿主。失败回滚保留旧活动来源；写入失败留下 pending 日志供恢复。
- pending 记录 `previousClient`，避免回滚旧运行快照时丢掉后来导入的非活动来源。配置独立保存节点选择；更新按协议/服务器/端口及完整连接参数的哈希身份保留节点 UUID，不按显示名匹配；选中节点消失则拒绝发布并保留旧版本。
- 第一份导入自动成为活动配置，其后新增保持当前活动配置。删除仅允许非活动来源，需先切换；防止删掉正在运行的配置。

## 当前格式能力（严格子集）

| 输入 | 当前行为 |
| --- | --- |
| flvp-profile v1 JSON | 保留当前 typed schema 支持的模式、节点、规则与最终策略 |
| Clash YAML/JSON | 九种协议严格子集；select / 非惰性 url-test / fallback 分组与基础规则，详见最新增量 |
| HTTP/SOCKS5 URI 每行一条，或对应 Base64 | 要求显式端口；支持百分号编码的用户名/密码；不支持 query 或路径参数；IPv6 地址可解析 |
| 手动单节点 | 无认证 HTTP/SOCKS5，默认最终 MATCH → PROXY，自动选中新节点 |
| 超出已实现子集的 Clash / Sing-box / V2Ray | 明确拒绝，不静默裁剪 DNS、Geo、provider 或未实现分组参数 |

节点列表默认最终策略 PROXY；完整原生 Profile 尊重其规则。导入不能设置本机监听、系统代理、路径或控制端口。远程下载使用 `clash.meta` User-Agent 请求 Clash 格式，显式直连，TLS 默认校验；总超时 20 秒、连接 10 秒、正文 1 MiB（流式累计限制）。当前拒绝重定向并要求最终 URL，不执行 provider 下载。最多 64 份来源、仓库 16 MiB、每份 256 节点/4095 规则，运行配置仍限制 512 KiB。

未接入订阅流量头/到期信息、配置编辑、导出、代理下载和策略组。无流量信息显示“未提供”；本地配置没有虚构的 URL、流量额度或到期日期。原单 Profile 读写接口仍用于已有基础测试，但未新增任何迁移流程或自动把旧 Profile 编进库。

## 用户提供的两个订阅（脱敏结果）

仅通过内存读取并统计结构，未保存 URL/token、节点服务器、名称或凭据到仓库。下述结果不代表已成功导入或节点连通。

1. 订阅 A：HTTP 200，约 15.5 KiB，完整 Clash，51 节点、2 策略组、7 规则。HTTP 22、Hysteria2 4、Hysteria 3、AnyTLS 8、VMess 2、SS 2、VLESS 10；含认证、TLS、Reality、WS 等字段。
2. 订阅 B：`FLVPcore/0.1` 返回 403；`clash.meta` 返回 HTTP 200 / 完整 Clash / 约 54.8 KiB；`v2rayN/6.42` 返回 HTTP 200 / URI 列表 / 约 11.1 KiB。共 30 节点：VLESS 10、Hysteria2 12、Trojan 8。

两份订阅均超出当前严格导入子集，**目前不能拿这两个订阅作为“导入即用”的完成验收**。下一阶段继续处理内核能力缺口和完整策略组/规则/DNS；不应仅为通过测试丢弃字段或筛掉不支持节点。

## 验证

- `flutter analyze`、44 项 Flutter 测试；覆盖解析拒绝、URL 脱敏、大小限制、UUID 身份、独立选择、事务回滚、发布失败恢复，及 720×640 窗口的新开关/手动创建。
- `flutter test integration_test/windows_configuration_test.dart -d windows`：真实 Windows 宿主 → 两个本地 HTTP 上游，验证手动创建、远程导入、运行中切换后请求分别抵达 A/B、重命名更新保留 UUID、非法更新保持原转发，以及本地文件删除后仍可重启加载快照。
- `.artifacts/ui/windows-tun-dashboard.png` 是设计 store 的布局截图（非真实节点数据），已目视核对并排开关尺寸、对齐和容器边界。
- 系统文件选择器已编译/接线，尚未自动化操作 Windows 原生选文件弹窗。没有验证真实订阅节点连接，没有 Android 构建/运行验收。

收尾补充：Windows 原有 `windows_smoke_test.dart` 再次通过；新增配置动作沿用设置草稿版本检查，避免下载/切换结束覆盖更新的端口或模式输入。原有 Android widget 测试只作为共享 Flutter 单测运行，没有 Android 平台构建或设备测试。


## 协议认证增量（2026-10-30，以上验证记录之后）

当前新增 `NodeOptions`、`WebSocketOptions`、`RealityOptions` 显式模型。Profile 序列化、导入、编译和宿主严格白名单贯通。认证与 TLS/传输参数参与节点身份，名称不参与；刷新时选中节点身份改变则保留原配置，要求先选择 DIRECT。不会将订阅原始 JSON 直接交给内核。

| 协议 | 当前明确开放的参数 |
| --- | --- |
| HTTP | Basic 用户名/密码、TLS、SNI、skip-cert-verify |
| SOCKS5 | 用户名/密码（各最多 255 UTF-8 字节）、UDP 标志 |
| SS | AES-128-GCM / AES-256-GCM / ChaCha20-IETF-Poly1305、密码、UDP；无 plugin / SS2022 |
| VMess | UUID、alterId=0、受限 cipher、TCP/WS、TLS/SNI/ALPN、UDP |
| VLESS | UUID、TCP/WS、TLS/SNI/ALPN、UDP；Vision 仅 TLS+TCP；Reality 仅 TCP、chrome 指纹 |
| Trojan | 密码、默认 TLS、SNI/ALPN、TCP/WS、UDP |
| AnyTLS | 密码、SNI、证书校验开关、UDP；TLS 隐含启用 |
| Hysteria 1 | auth-str 密码、整数 Mbps up/down（兼容 `11 Mbps` 输入）、SNI/ALPN、证书校验开关 |
| Hysteria 2 | 密码、SNI、证书校验开关；固定端口，无端口跳跃/混淆配置 |

WS 仅支持 path/headers，拒绝控制字符、重复 header、保留握手字段及 early-data。指纹根据固定内核的实际实现限制：普通 TLS 忽略 fingerprint，所以显式拒绝；Reality 的 uTLS 仅实现 chrome，拒绝 ios/random 等，不能通过替换指纹伪造兼容。

宿主在停止旧运行实例之前，逐个调用 eager outbound construction（不拨号）进行预检，避免惰性构建把 UUID/加密套件/Reality 配置错误延后到首次请求。预检成功与 listener ready 均不代表远端连通。

原文、认证参数和运行快照目前保存在当前用户应用数据目录，**尚未做 DPAPI 凭据加密**。日志、诊断、仓库 fixtures 不写真实 token、密码、UUID 或服务器。手动创建 UI 仍仅无认证 HTTP/SOCKS5；高级参数通过严格节点列表/native Profile 导入。

本轮实测：48 项 Flutter 测试、10 项 Rust 宿主测试、clippy、12 项真实本地宿主转发检查（新增 HTTP Basic 和 SOCKS5 认证）、Windows 配置集成和 smoke 均通过。上游 vendor 本地 loopback 22 项通过，包含 SS/VMess/VLESS/Trojan/AnyTLS/Hysteria 1/2；这仅证明本地协议回环，不等同于公网互通。Windows Release 已构建。

真实订阅仅在内存中探测：A 51 个节点中 41 个通过单节点校验，B 30 个中 8 个通过；按每份订阅每协议最多 1 个受支持节点抽样，8 个本地监听均 ready，HTTPS `example.com` 请求 **0/8 成功**。不得据此称订阅可用，也不能推断全部节点不可用。完整导入均仍拒绝：A 有 2 分组/7 规则（含 GEOIP）；B 有 14 分组/594 规则（含 IPv6 CIDR、GEOIP）、fake-ip DNS/respect-rules/多项 nameserver/fallback 语义，及 Hysteria2 ports/mport 和尚未支持的指纹。

复验入口 `tools/verify_subscriptions_test.dart`，从进程环境 `FLVP_TEST_SUB_A` / `FLVP_TEST_SUB_B` 接收 URL。只输出结构计数，不存储订阅；脚本完成不代表连接成功，必须读取 connected/failed 计数。该诊断工具拆分节点仅用于定位，不改变产品“完整配置不静默裁剪”的策略。

最后一次抽样失败分类：A 的 Hysteria2 为 15 秒总超时，其余 6 个为客户端 TLS 握手失败；B 的 Trojan 为 HTTP 代理异常。未捕获到 `CERTIFICATE_VERIFY_FAILED`，尚不能定位为证书信任问题或某一内核协议缺陷。下一阶段应补充脱敏的宿主握手阶段诊断，再验证真实公网请求。


## 策略组与规则增量（2026-10-30，最新）

- 新增 `PolicyGroup` typed schema，支持 `select`、`url-test`、`fallback`，每 Profile 最多 64 组、每组最多 320 成员、嵌套深度 16。UUID 引用节点/组，禁止重名、重复成员、循环、缺失引用与引用保留全局选择器。宿主有独立边界校验，预检失败不停止工作中的旧实例。
- 自动组目前要求明确 `lazy: false`、HTTP(S) 测试 URL、30–86400 秒间隔；URL-Test 容差 0–60000 ms。固定内核的 lazy 模式没有完整周期测速，暂不开放；load-balance、relay、provider、disable-udp 等仍拒绝。
- Clash 基础规则现在保留输入顺序，支持 DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD / IP-CIDR / IP-CIDR6 / NETWORK / DST-PORT 与唯一末尾 MATCH；IP-CIDR6 规范化为支持 IPv6 的 IP-CIDR。不得省略 MATCH、附加未知修饰符，no-resolve 仅限 CIDR。Geo/规则集资源依旧拒绝，不能让内核静默跳过。
- 允许读取并校验 Clash 设备字段 mixed-port/port/socks-port/allow-lan/bind-address/external-controller/log-level，但这些字段不进入运行快照，继续使用客户端 loopback 监听和设置。其他未知顶层选项拒绝。导入提示已说明本机设置归属。
- 规则模式按导入分组/规则执行；全局模式继续使用原 PROXY 节点选择，直连模式 MATCH,DIRECT。后两种模式不装配订阅策略组，避免额外后台健康检查连接。
- 节点页显示各策略组。select 有独立下拉选择，自动组标注内核自动选择，不捏造当前最快节点/延迟。选择通过原有快照事务重启应用；独立保存，重启和订阅更新保持。组身份按精确名称+类型匹配（不猜测重命名）；若更新移除已选择成员，拒绝更新并保留旧配置。

验证：52 项 Flutter 测试通过；Rust 10 项与 clippy 通过；真实宿主 12 项转发通过。新增真实 Windows runtime 测试验证 manual A→B、按 DOMAIN 路由到 Fallback、URL-Test 失败成员切换、重启后保持 B。UI 集成单独验证下拉选择驱动真实转发。

### 公网探测结论更新

为排除 Dart TLS 客户端影响，在同一 Windows 宿主抽样节点上加入独立 `curl.exe`（证书校验保持开启）复验：订阅 A 的 **Hysteria、AnyTLS、Shadowsocks 各一个样本 HTTPS 成功**（目标返回 200 且含预期正文），8 个样本合计 3 个成功。HTTP 样本 curl 进程成功但响应未满足验收，Hysteria2 超时，VMess/VLESS TLS 握手失败，B Trojan 代理连接失败。原 Dart 路径依旧 0/8，其原因未定位；不能继续用该结果代表所有出站不可用。此为抽样，不能推断同协议全部节点。

两份真实订阅依旧不能直接完整导入：A/B 均还有 Geo 和未知顶层语义，A 含 lazy 组与指纹问题；B 另含 DNS、load-balance、Hysteria2 端口跳跃等。后续优先明确内核升级/适配边界，补齐完整语义，不删除用户订阅字段绕过。
