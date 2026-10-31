# FLVPcore 开发交接

更新：2026-10-30。工作区：`D:\FLVPcore`。本文供新会话直接接续，区分已实现能力、用户已确定的产品方向与待验证的实现方案。

**最新接续入口：先读第 14–16 节，尤其第 16 节的收工状态和明日任务。** 前半部分保留早期调研/设计历史，不代表当前待办；vpn-parser 调研、Windows 系统代理、配置仓库、协议/策略组、分享链接及普通代理 DNS 子集都已有实现。用户最新方向仍为 **Windows 优先、暂停 Android、不做旧数据迁移、不自动更新内核、保留现有 UI，优先订阅兼容**。

## 1. 新会话第一个任务：调研 vpn-parser，再开始下一阶段开发

用户新增参考项目：`D:\FLVPcore\cilent-example\vpn-parser`。目录已经确认存在，包含 Rust 工程、README、docs、发布记录等；**本会话尚未完成技术调研，不要把下面的用户线索当作已经核验的实现事实。**

用户提供的线索：这是 vp_core 作者制作的多内核代理客户端，近期已加入 vp_core 支持；支持 Windows、Linux、macOS，提交记录显示还在进行 Android 支持。

新会话按以下顺序行动：

1. **先研究 vpn-parser。** 确认来源、许可证、版本／提交与 vp_core 依赖版本；若本地无 Git 元数据，查明来源后再核对上游，不能编造提交历史。
2. 定位 vp_core 适配器及实际调用链，区分哪些能力由 vp_core 提供，哪些仅适用于其他内核。重点核对配置转换、订阅格式、节点／策略组选择、IPC、生命周期、系统代理、TUN、DNS、路由恢复，以及 Android 的实际完成程度。
3. 针对 Android 查看相关实现与近期提交，区分占位、开发中和已可运行；尤其检查 VpnService、socket protect、FD 所有权、JNI、前台服务及网络切换。
4. 形成“代码依据 → 可借鉴方案 → 与 FLVPcore 的差异 → 需要验证的事项”。建议新增 `docs/client-reference-vpn-parser.md`，并按实际发现更新现有配置、规则及两端生命周期文档。记录文件位置和提交依据；不把支持其他内核的功能直接算作 vp_core 已支持。
5. 对照现有 FLVPcore 实现，评估是否能替代或补强此前方案。借鉴前核对许可证；不要为了参考实现随意替换当前固定内核或覆盖用户界面。若新证据推翻旧调研，应更新结论并保留依据。
6. **先完成调研并吸收到文档，再进入系统代理、TUN、订阅开发。** 不应只补一个参考链接就跳过调研，也不应把整个新会话停在规划阶段。

此任务之后的建议开发顺序见第 7 节；应根据此次调研调整具体实现，但保持用户的产品方向。

## 2. 用户已确定的方向

FLVPcore 定位：**开箱导入订阅即用，但高级配置能力也不会缺。**

当前只开发 Windows 和 Android；两端稳定、功能完善后再考虑其他平台。使用 Flutter + Dart，共享业务模型和配置编译，平台层负责系统能力。

用户对订阅与节点的明确要求：

1. 常规订阅导入，支持导入**本地配置文件或链接**。
2. 支持**手动创建**：主要用于更容易理解、更方便地使用单节点，将单节点做成本地配置。
3. **节点页只显示选中的订阅。** 不做所有订阅节点混在一起的全局节点池。

以下是承接上述要求的建议实现语义，尚未编码，不代表已经存在这些字段或接口：

1. 统一配置来源模型：远程订阅、从文件导入的本地配置、手动创建的本地配置。三者都能成为当前活动配置；“手动创建”不是绕开配置仓库的临时节点。
2. 导入文件应保存在应用可管理的本地快照中；不要假定原文件路径长期可读。远程来源保留更新地址及获取元数据，手动来源不虚构 URL、流量额度或到期时间。
3. 使用稳定的来源／配置 ID 表达归属，节点名和 `NodeInfo.sub` 显示文字不能充当关联键。各配置单独保存节点选择，切换后只展示对应配置的节点／策略组，不带入别的订阅选择。
4. 区分“当前选择的配置”和“已经应用的运行快照”；运行中切换或更新通过事务完成。应用失败保留上一次有效运行状态，不把界面切到一份未生效配置却仍显示成功。
5. 不把所有订阅当成纯节点列表。完整配置中的规则、策略组、DNS、provider 等语义应在兼容能力允许时保留；节点列表型订阅则通过明确的客户端默认策略生成可用配置。
6. 手动单节点配置需要明确的默认代理策略，避免默认最终规则为 DIRECT 导致“导入即用”失效。完整配置尊重其规则，不一律强改全局代理。
7. 常见格式应基于真实 schema／fixtures 逐步覆盖。不能从设计界面的“支持 Clash、Sing-box 与 V2Ray”文案推断已经支持。未知协议、关键字段、无法实现的规则必须给出诊断，不静默丢弃再显示导入成功。
8. 高级能力包括自定义规则、策略组、DNS、本机覆盖、配置查看／编辑及导入导出；应保留扩展空间。不要用只支持“节点名称、地址、端口”的永久数据模型锁死产品。

切换后的内置 DIRECT／REJECT 等策略是否作为节点页独立项目，需要沿用界面设计并明确语义；它们不属于其他订阅的节点。

## 3. 界面与工程布局：保留用户成果

用户已亲自完成基本 1:1 的设计复刻，并明确要求：**不用再做前端，继续代理开发。**

1. 保留当前视觉、交互、动效和 Windows 自定义顶栏。风格是大量 MD3 + 少量 Fluent，以色差和阴影分区，不增加分割线，不替换页面和组件。
2. 可以进行必要的数据接线、真实状态展示和业务文案修正。新增本地文件导入／手动配置入口时，复用现有设计语言与组件，避免借功能开发重新设计整套界面。
3. Flutter 工程直接位于根目录：`pubspec.yaml`、`lib/`、`windows/`、`android/`。用户明确不需要再嵌套 `app/` 或另一层项目目录。
4. 设计原稿在 `UI-design-pages/`。参考源码在 `core-example/vp_core/`、`cilent-example/FlClash/` 与新增的 `cilent-example/vpn-parser/`。
5. `lib/ui/client_shell.dart` 是保留的旧功能编辑界面，**不是正式入口**；不要恢复它来替换用户的新界面。

## 4. 当前真实实现基线

固定 vp_core v1.1.0 提交：`fa3e7430371930c440ffb1bdccc6869c63554a34`。自有 Rust 宿主在 `native/core-host/`，两端复用同一生命周期和受限配置编译。

| 项目 | 已实现 |
| --- | --- |
| 普通代理 | 绑定 `127.0.0.1` 的 HTTP／SOCKS5 混合入站，默认端口 17890 |
| 上游节点 | 无认证 HTTP／SOCKS5；并非已支持内核的全部协议 |
| 规则 | DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、NETWORK、DST-PORT、最终 MATCH |
| 业务模式 | 规则／全局／直连，确定性编译成 core `rule` 模式与显式最终 MATCH |
| 配置 | 严格 `flvp-profile` v1、UUID 引用、SHA-256、不可变 runtime snapshots、pending 日志、失败重启回退 |
| Windows | Flutter → JSONL stdin/stdout 子进程 → 自有 Rust Host → `vp_app::App` |
| Android | MethodChannel → Kotlin 单线程执行器 → JNI → 同一 Rust Host；普通代理前台服务拥有运行时 |
| 新界面接线 | 真实启停、持久化节点读取、节点选择、模式、混合端口、流量与错误反馈 |
| 生命周期 | 启动中再次停止、配置应用失败回退、Windows 退出清理、Android 控制器重新接入运行中的服务 |

**尚未实现：** Windows 系统代理、Windows TUN、Android VPN/TUN、真实订阅、本地文件导入／手动创建在新页面中的入口、完整协议与认证、策略组完整模型、复杂规则／Geo／provider、节点测速、托盘驻留和自动启动。

当前系统代理、TUN、订阅等 store 操作会明确提示尚未实现。更新检查／备份等部分设计动作仍是占位；主题选择未持久化。不要把按钮存在视为后端已完成。

当前正式入口链路：

```text
lib/main.dart
  → FlvpApp + FlvpClientStore
  → ClientController → CoreBridge → HostTransport
  → WindowsHostTransport / AndroidHostTransport
  → native/core-host
```

关键文件：

| 路径 | 用途 |
| --- | --- |
| `lib/ui/store/client_store.dart` | 正式数据适配器；串行操作、650ms 端口防抖、保留较新的设置草稿、未实现能力反馈 |
| `lib/ui/store/design_store.dart` | 可注入的设计演示 store；正式入口使用子类并禁用模拟定时器 |
| `lib/ui/store/models.dart` | 页面模型；目前不等于正式订阅仓库模型 |
| `lib/core/profile.dart` | 当前受限 Profile／节点／规则模型及严格解析 |
| `lib/core/compiler.dart` | 确定性编译，编译器版本 `m0.1` |
| `lib/core/snapshot_store.dart` | 原子存储、快照、应用日志及恢复 |
| `lib/core/controller.dart` | 串行启停／保存／应用；约 2 秒状态轮询 |
| `lib/core/bridge.dart`、`transport.dart` | 协议 v1 与平台传输 |
| `lib/core/traffic.dart` | 单调时间差分速率、generation 重置与进程内累计 |
| `native/core-host/src/` | 自有宿主、严格配置校验、ready、回退和 JNI |
| `android/app/src/main/kotlin/io/flvpcore/app/` | MainActivity、CoreRuntime、ProxyService、CoreNative |

Bridge 当前操作是 `capabilities/status/start/apply/stop/quit`。写操作带 `requestId`、`expectedGeneration`、`expectedAppliedRevision`，快照参数含 revision、config 文本和 configHash。扩展能力应明确版本／能力协商，不假定早期设计接口已经实现。

`ClientController` 捕获操作异常并记录 `error/status`，不能因为 Future 正常返回就当作业务成功。运行中选择节点／修改配置会完整重启并可能断开连接。

流量是内核采样的真实字节差分；“累计”目前只在本次客户端进程内保存，界面运行时长从本客户端首次观察到运行开始，不是服务原始启动时间。

## 5. 存储与迁移约束

正式入口直接使用 `getApplicationSupportDirectory()`，**不要再附加 `flvpcore/` 子目录**，否则会找不到已经保存的配置。当前 Windows 用户目录通常为 `%APPDATA%\io.flvpcore\flvpcore`。

```text
state/client.json          活动 Profile + 本机 mixedPort / selectedNodeId
state/pending.json         未完成的应用日志
state/applied.json         已核对的运行快照指针
runtime/<revision>/        config.json + snapshot.json
staging/<uuid>/            发布临时目录
```

1. 当前只持久化一份活动 Profile，**还没有多配置／订阅仓库**。现有 `SubInfo` 是页面数据形状，不能直接当成完整仓库。
2. 下一阶段需要带 schema 版本的迁移：将既有 Profile、节点 UUID、规则、选择和端口接入新的本地配置项。保留备份与恢复路径，不用演示数据覆盖用户原有 HTTP 节点。
3. 维持来源原文、规范化业务模型、设备设置、用户覆盖、运行快照的边界。远程订阅不能覆盖本机控制端口、文件路径、系统接管或凭据管理策略。
4. 更新下载、解析、引用校验、编译和资源准备通过后再发布快照；应用失败保留旧配置。不要让客户端和内核各自刷新远程 provider，破坏回滚的一致性。
5. 订阅更新按可靠身份保留 UUID，不能仅凭同名复用节点。节点消失或引用失效要显式诊断；旧 M0 的节点移除后重置 DIRECT 行为不应直接照搬成订阅更新策略。
6. 当前限制：节点至多 256、规则至多 4095，Profile 文本至多 1 MiB，运行配置至多 512 KiB，宿主请求帧至多 1 MiB。真实订阅可能超限，应跨 Dart、传输、宿主与测试一起评估，而不是只改一个常量。
7. 日志和交接材料不记录真实订阅 token、认证头或节点凭据。认证／高级协议需要正式字段与凭据方案，不能临时拼接到显示名称或 URL 字符串中。

## 6. 已知内核问题与平台阻塞项

### P001 与普通代理

真实测试发现上游 HTTP 入站把 `host:port` 整体作为 DNS 主机名。项目选择性 vendor `native/vendor/vp-protocol/`，通过 Cargo patch 修复 authority、显式端口和 IPv6 解析；其余 core crate 仍固定 Git 提交。

能力标识包含 `+P001`。补丁来源见 [vendor 说明](native/vendor/README.md)。保持 `core-example/vp_core` 作为参考，不用修改参考 checkout 来代替正式构建补丁。

上游 `validate` 对未知字段、部分未知规则和数值溢出不够严格；现有客户端／宿主增加了白名单与边界校验。宿主还验证监听归属和真实 SOCKS 握手，不能只凭 `vp_app::App` 装配返回就认定成功。

### Windows 系统代理

1. 基于当前用户 WinINet 配置与刷新通知实现，不默认修改 WinHTTP、其他用户或全局系统设置。
2. 先验证本实例监听可用，再启用系统代理。写入前持久化原值、本实例写入值与事务归属，覆盖受影响的手动代理、绕过、PAC／自动发现设置。
3. 停止、失败或下一次启动恢复时，仅在当前值仍匹配本实例写入值时恢复；用户或其他代理中途更改则报告冲突，不覆盖新设置。
4. 明确 Windows 系统代理和 TUN 的互斥／切换策略。Android 普通应用没有等价的通用系统代理接管，应通过 VPN 能力实现整机接管。

### Windows TUN

1. **不要直接托管上游 CLI `run`。** 调研发现其正常退出可能广泛清理双 `/1` 路由，影响其他 VPN；现有自有宿主避开该路径。
2. 需要验证 Wintun 来源、匹配架构、加载路径、权限宿主、节点及 DNS 逃逸、接口选择和逐项归属恢复；不能只打开 `tun.enable`。
3. 路由／DNS 必须有写前日志和崩溃后恢复主体，清理只针对本实例。普通与提权运行时切换不得同时保有两个活动内核。

### Android VPN/TUN

1. 当前 `ProxyService` 是普通代理前台服务，**不是 VpnService**。VPN 授权、撤销、服务状态及 FD 契约尚未实现。
2. 所有自建出站 socket 的 protect／底层网络绑定需要覆盖 DIRECT、代理、UDP／QUIC、DNS、测速和重连等路径。不能只补一个 TCP dialer，或依赖 Dart／页面回调。
3. 明确 FD 所有权；现有上游消费 FD 的边界和失败返回不足以可靠判断转移。原文档建议 borrowed FD → native 立即 dup → 各自关闭所有副本，需核验后实现并测试全部错误路径。
4. 修复／统一 DNS 与 FakeIP 映射、bootstrap 逃逸及 TUN 包读写取消语义；不能让系统已接管但 native 未 ready 的接口长期留存。
5. 授权中停止、`onRevoke`、后台通知停止、Activity 重建、网络切换都进入同一原生状态机。always-on／lockdown 要另行完成验收，不能默认承诺。

上述结论基于当前固定版本和既有调研；vpn-parser 可能提供新补丁或方案，应在第一个任务中逐条核对。

## 7. 调研之后的建议开发顺序与验收

1. **Windows 系统代理闭环。** 实现原值保存、启用、正常停止恢复、宿主故障恢复、下次启动恢复及外部修改冲突检测；验证 PAC／自动发现和用户已有代理不会被损坏。
2. **共享配置／订阅仓库。** 先落实三种来源、多配置切换、旧数据迁移，再接入文件选择、链接获取、手动单节点创建。节点页严格绑定活动配置；更新失败保留有效版本，完整配置保持高级语义。测试 Windows／Android 得到一致规范化与编译结果。
3. **Android VPN/TUN。** 先完成 protect、FD、DNS／FakeIP 与 ready，再开放 VPN；覆盖 TCP／UDP、撤权、启动中停止、网络切换和失败释放。
4. **Windows TUN。** 建立权限边界、路由／DNS 事务、绕行及崩溃恢复；验证 IPv4／IPv6 策略、多网卡、睡眠恢复，以及其他 VPN 路由不受影响。
5. 每个增量完成真实闭环后更新能力清单、文档和测试。认证协议、策略组、provider 等要同步扩展 typed schema 和宿主校验，不能只在导入器中放行。

这是依赖驱动的建议顺序，不是已经完成的承诺。vpn-parser 的实证调研结果可调整顺序和拆分。阶段验收应区分普通代理、系统代理和 VPN/TUN 的真实状态；本地 listener running 不等于已经整机接管或上游连通。

## 8. 工具链、构建与已有验证

上次验证环境：Windows x64 / PowerShell，Flutter 3.47.7、Dart 3.13.5、Rust 1.95.0、Android SDK 36、NDK 28.2.13676358、JDK 17。Flutter 在 `E:\flutter`，Android SDK 在 `%LOCALAPPDATA%\Android\sdk`；新会话以实际环境为准。

从项目根目录执行：

```powershell
flutter analyze
flutter test
python tools/verify_host.py
python tools/verify_research.py --docs-only

./tools/build_windows.ps1
./tools/build_android.ps1

flutter test integration_test/windows_smoke_test.dart -d windows
# Android 使用同一集成测试文件，替换为实际设备 ID。
flutter test integration_test/windows_smoke_test.dart -d <android-device-id>
```

仅构建原生部分可给脚本加 `-SkipFlutter`。Android 构建脚本生成 arm64-v8a／x86_64 的 `libflvp_host.so` 并采用 16 KiB LOAD 对齐；默认产物是开发签名 Debug APK，不代表真机／商店兼容性全部验收。

修改宿主或补丁时的额外检查：

```powershell
cargo test --locked --manifest-path native/core-host/Cargo.toml --lib
cargo clippy --locked --manifest-path native/core-host/Cargo.toml --all-targets -- -D warnings
cargo test --locked --manifest-path native/vendor/Cargo.toml -p vp-protocol flvp_p001_tests --target-dir native/core-host/target
```

**上一轮已实际通过，供新会话作为基线，不代表新修改自动通过：**

1. `flutter analyze` 无问题；31 项 Flutter 单元／组件测试通过。
2. 10 项真实宿主检查通过：HTTP／CONNECT／SOCKS5 入站、HTTP／SOCKS5 上游、失败回退后转发、过期停止、流量计数、EOF 释放监听。
3. Windows 集成通过：新 store 驱动真实宿主、HTTP 请求、流量、端口冲突回退、模式切换、运行中关闭释放端口。
4. Android 17 x86_64 模拟器集成通过：真实 JNI／前台服务、同样转发与回退、旧控制器销毁后重新接入同一 generation。不是 VPN 测试，也不是真机验收。
5. 无人值守 Android 测试曾向测试模拟器授予通知权限，未据此证明拒绝权限场景。AVD 为 `Medium_Phone`，上次临时端口 `5580`，测试完成后已关闭，不能假定仍在线。
6. Windows Release 和 Android 双 ABI Debug APK 均构建成功；Markdown 文档链接检查通过。

产物路径：`build/windows/x64/runner/Release/flvpcore.exe`（保留同目录 DLL、data、host）与 `build/app/outputs/flutter-apk/app-debug.apk`。运行集成测试会重新生成测试入口 APK，最终交付前应重新构建正式入口。

主要回归测试：`test/client_store_test.dart`、`test/traffic_test.dart`、`test/controller_test.dart`、`test/configuration_test.dart`、`test/widget_test.dart`。设计截图测试在 `integration_test/ui_capture_test.dart`，使用演示 store，不代表真实代理验收。

## 9. 文档导航与阅读注意

1. [当前 Flutter 接线与限制](docs/flutter-client.md)：当前正式入口的能力说明。
2. [M0.1 实施记录](docs/m0-implementation.md)：宿主、快照与最初功能基线；旧节点／规则编辑器描述不能当作新页面已接入。
3. [验证记录](docs/verification.md)：调研阶段与后续接线验证分开记录。
4. [内核调研](docs/core-research.md)、[配置规范](docs/configuration.md)、[规则规范](docs/rules.md)：完整设计与上游事实，很多高级能力尚未实现。
5. [Windows 通信与生命周期](docs/bridge-windows.md)、[Android 通信与生命周期](docs/bridge-android.md)：平台架构及接管方案。开头的早期“尚未实现”状态不代表普通代理宿主仍不存在；以源码和较新的实施记录为准。TUN／系统接管部分仍待实现。

开始工作先检查当前 Git 状态和文件，不回滚用户改动，不重新生成／覆盖已经完成的 UI。**本次交接仅新增文档；下一会话先完成 vpn-parser 调研，再推进系统代理、TUN 和订阅。**

## 10. 后续增量：Windows 系统代理（2026-10-30）

已完成 vpn-parser 参考调研并记录于 `docs/client-reference-vpn-parser.md`。用户明确希望借鉴独立内核的解耦设计，不做自动内核更新；当前仍保持固定 Rust 集成，外置运行时是需独立验收的后续目标。

Windows 当前用户 LAN WinINet 系统代理已接入现有开关：先启动本地代理，再开启；停止恢复，运行中改端口会恢复/重新接管；原值/PAC/自动发现、SID 与写入值保存在 `state/system-proxy.json`，数据根独占锁为 `state/network.lock`。只修改 WinINet LAN 设置。发生外部修改时保留新值并报告冲突，不覆盖、不自动抢回。正常 EOF/退出恢复；宿主异常退出由 Flutter 拉起 `--recover-system-proxy`，UI/Host 同时退出后下次启动恢复。

已验证 Flutter 32 项单测、Rust 8 项测试与 clippy、10 项普通代理宿主验收、真实 WinINet 验收脚本，以及 Windows 带系统代理的完整 store 集成。具体命令/限制以 `docs/verification.md` 与 `docs/bridge-windows.md` 新增段落为准。下一阶段建议推进共享配置/订阅仓库，保持三种来源、活动配置节点隔离和旧数据迁移要求。Android 系统代理/TUN 仍未开放，未改原有 UI 风格。

## 11. 最新方向及配置仓库（2026-10-30）

用户最新决定覆盖本文早期建议：**不做旧数据迁移；先只做 Windows，暂停 Android 开发/构建**。Windows 仪表盘系统代理旁新增同样式 TUN 开关，后端尚不可用，点击明确拒绝，不会假开启。

多配置仓库、文件快照、手动无认证 HTTP/SOCKS5、受限订阅导入、来源隔离、独立选择、运行中切换和更新事务已实现。细节与验收见 `docs/windows-configurations.md`。用户提供两个真实测试订阅，已脱敏调研：A 为 51 节点完整 Clash（含多种高级协议/认证），B 为 30 节点 VLESS/Hysteria2/Trojan；B 需要 Clash/v2rayN User-Agent，默认下载已改用 `clash.meta`。**当前子集仍不能完整导入这两个订阅**，下一阶段优先扩展其协议认证与策略组/规则/DNS schema，不得过滤字段伪造成功。真实 URL/token 不写交接文档、测试 fixtures 或日志；需要时从用户对话取得。


## 12. 最新增量：协议参数与订阅探测（2026-10-30）

Windows only / 无迁移 / 固定内核且无自动更新继续生效。已扩展九种协议的严格节点参数子集：HTTP、SOCKS5、SS、VMess、VLESS、Trojan、AnyTLS、Hysteria 1/2。实现位置为 `lib/core/node_options.dart`、`profile.dart`、`configuration_importer.dart`、`compiler.dart`、`native/core-host/src/node_options.rs`、`config.rs`；宿主构建前做 eager outbound 预检，不联系远端。配置身份现在包含认证/TLS/传输参数的哈希，更新不会把同地址不同账号节点认作相同；选中身份变化仍拒绝更新。

**两份真实订阅仍不能完整导入。** 不要误读新协议支持为完整 Clash 支持。固定内核普通 TLS 会忽略指纹，Reality 仅支持 chrome；Hysteria2 不支持 ports/mport。客户端与宿主明确拒绝这些语义，不丢字段、不替换指纹。后续还需实现策略组/引用图、GEOIP 资源可用性与规则、完整 DNS 语义；B 包含 fake-ip、respect-rules 等不能简单映射。

新增脱敏 fixture、参数/身份回归、Dart→真实 Windows host 契约测试。48 Flutter、10 Rust host、clippy、12 本地宿主转发（含 HTTP/SOCKS5 认证）、22 vendor loopback、两个 Windows 集成均通过。Release 构建成功。真实订阅探测 A 单节点校验 41/51，B 8/30；每协议抽一个受支持节点，共 8 个均 listener ready，HTTPS 0/8 成功，未完成公网连通验收。细节见 `docs/windows-configurations.md`。探测工具从环境变量接收链接，不落盘真实订阅；环境与工具输出仅保留脱敏计数。凭据在用户应用数据/快照中仍为明文，尚未引入 DPAPI。


## 13. 最新增量：策略组、基础 Clash 规则与公网复验

实现 typed `PolicyGroup`、Clash select/url-test/fallback（后两者仅显式 lazy:false）、UUID 引用图/循环/深度校验、规则引用转换、独立组选择持久化/刷新保留、节点页下拉控件，运行配置与 Rust 白名单同步扩展。规则模式遵循策略组；全局/直连模式省去导入组，避免后台探测。Geo、DNS、load-balance、lazy:true 及其它未实现语义仍拒绝，两个真实订阅仍不能完整导入。具体字段与本机设置归属见 `docs/windows-configurations.md` 最新段落。

公网结论有重要更新：同样 8 个样本额外用 Windows curl 复验，A 的 Hysteria / AnyTLS / SS 各 1 个成功（HTTPS 200 + 预期正文），合计 3/8；Dart HttpClient 仍 0/8，差异未定位。不可再简单描述为“全部公网节点不可用”，也不可宣称整个订阅已可用。诊断脚本只输出计数和 curl exit code，真实 URL 仍从对话/进程环境读取，未落盘。

新增 `test/policy_groups_test.dart`、`test/policy_group_runtime_test.dart` 和 `integration_test/windows_policy_test.dart`。前者验证格式/图/更新；真实 runtime 验证规则分流、自动组失败成员切换、手动 A→B、重启选择；UI 集成验证下拉控件到真实 HTTP 上游。Windows only、无迁移、固定内核无自动更新继续生效。

## 14. Windows 分享链接导入（2026-10-30）

最新已实现：节点列表支持 HTTP、SOCKS5、VLESS、Trojan、Hysteria2 / `hy2` URI，及 UTF-8 Base64 / Base64URL 列表。VLESS 支持内核已有的 TCP/WS、TLS/Reality、SNI/ALPN、Vision、Host/path；Trojan 支持 TLS/SNI、TCP/WS；Hysteria2 支持密码、SNI 和证书校验。入口为 `lib/core/share_link.dart`，复用 `NodeOptions`、身份哈希、配置仓库刷新事务和 Rust eager outbound preflight。分享 URI 是节点列表，不承载完整规则/组/DNS。未知/重复 URI 参数、未实现传输/端口跳跃/混淆、无端口、损坏凭据会拒绝整份列表；错误包含行号但脱敏。

新增 `test/share_link_test.dart`、`test/share_link_runtime_test.dart`。已通过：`flutter analyze`、完整 `flutter test`（58 项）、真实 Windows host 的分享协议预检，以及独立本地 VLESS v0 peer 的真实 HTTP 转发；集成检查包含 Base64 远程导入、更新重命名保留 UUID 和选择、非法刷新保留原 revision、重启恢复和再转发。Windows Release 已构建，Release host 的 12 项转发/生命周期检查及 36 个文档链接检查通过。未重新探测真实用户订阅。完整 Clash 订阅 DNS、Geo/GEOSITE、provider、load-balance、Hysteria2 ports/mport、非 chrome 指纹仍是明确缺口；TUN 继续保持关闭占位。Android 仍暂停。

## 15. Windows 订阅 DNS resolver（2026-10-30）

按用户要求继续深入参考 `cilent-example/`，重点核对 vpn-parser VP-Core 编译器（仍为 4735038）与 FlClash typed DNS 模型（7fd417f）。发现 vpn-parser 会删改 policy/添加 DNS 上游和 Geo URL；不将其转换视为无损兼容。固定 vp_core 普通代理可使用自定义 resolver，53 端口监听在 TUN 路径才启动。依据/差异/行为边界见 `docs/dns-compatibility.md`。

新增 `lib/core/dns_options.dart`，Profile 级持久化、订阅导入/刷新与编译贯通；Rust `native/core-host/src/dns.rs` 独立校验。支持 redir-host、IPv4 查询、UDP/TCP IPv4、DoT IPv4、DoH、非 Geo fallback-filter 的 CIDR/+.domain。DNS 在规则/全局/直连模式均保留。拒绝 Fake-IP、listen、default-nameserver、nameserver-policy、respect-rules、Geo、IPv6 查询等未知/未生效语义；不改系统 DNS/路由、不创建 DNS listener。编译器版本 windows-dns.1。P002 选择性 vendor vp-dns，给 DoT connect/TLS/read 整体加 3 秒期限，其余 core 仍固定原提交，无自动升级。

已通过 analyze、63 项 Flutter、12 项 Rust host、clippy、DNS crate 23 项本地测试和 4 项单独启用的公网 DoH/DoT 测试。Debug/Release host 均通过新 DNS runtime 2 项测试（节点 bootstrap/DIRECT、UDP/TCP、过滤/fallback、非法刷新保留旧 revision、DoT 3 秒回退、重启持久化），Release host 原有 12 项验收通过。Windows 正式入口 Release 已构建。未重新请求用户真实订阅，未构建 Android；完整 Clash 两份订阅仍不能无损导入。下一步仍需 Geo 资源快照/规则、lazy/负载均衡、Fake-IP/respect-rules 与指纹/端口跳跃等完整语义，不通过过滤字段伪造成功。

## 16. 收工与明日接续（2026-10-30 → 2026-10-31）

### 当前状态

1. 本轮代码与文档仍在工作区，**尚未提交 Git**，包含未跟踪的新文件；新会话先 `git status --short`，不要 reset/clean 或覆盖这些成果。没有留下需要继续等待的构建、服务或模拟器任务。
2. 最新正式入口 Windows Release 位于 `build/windows/x64/runner/Release/flvpcore.exe`，必须保留同目录 `flvp-core-host.exe`、DLL 与 data。本轮最终构建已包含分享链接和 DNS 增量；不要仅凭 runner exe 的旧修改时间判断 Flutter 业务代码未更新，Dart AOT 在 `data/app.so`。
3. 最终验证：analyze 无问题，完整 Flutter **63 项**、Rust host **12 项**、clippy 通过；DNS crate **23 项本地 + 4 项显式启用的公网测试**通过；Release host 新 DNS runtime **2 项**及原有转发/生命周期 **12 项**通过；文档 **46 个**本地链接和代码围栏检查通过。复现细节见 `docs/verification.md` 最新段落。
4. 本轮没有修改用户系统代理、Windows DNS 或路由，没有构建 Android，没有重新下载用户真实订阅。普通代理 resolver 与整机 DNS/TUN 接管仍是不同能力。公网 DNS 测试成功不等于用户代理节点或完整订阅成功。

### 明日建议推进

1. 继续优先**完整订阅兼容**。重点参考 `cilent-example/vpn-parser/`，并对照 FlClash 的字段模型；定位到源码、说明转换差异，再落入 FLVPcore typed schema、compiler、宿主独立校验和快照事务。既有参考结论见 `docs/client-reference-vpn-parser.md`、`docs/dns-compatibility.md`，无需重新把整个会话停在基础调研。
2. 建议先选 **Geo 资源与 GEOIP/GEOSITE 规则闭环**：资源来源/版本/许可、大小和摘要、准备完成后随不可变快照发布、类别存在性预检、启动/回退时使用同一资源版本。固定内核缺资源会静默跳过规则，不能仅在导入器放行；也不能直接复制 vpn-parser 注入远程 URL、删除/替换规则的做法。不得让内核后台自行更新资源破坏快照一致性。
3. 随后评估 **lazy 自动组和 load-balance**。当前仍仅 select、显式 lazy:false 的 url-test/fallback。已读源码中的待验证疑点：固定 `vp-router::Group::start_health_checks` 在 lazy=true 时直接退出；`Router::resolve_via` 会调用 `Group::pick`，负载均衡 connect 时可能再次选择，需独立测试真实轮询结果和统计归属。此处是源码疑点，尚未实现补丁或完成复现，不要写成已修复。
4. DNS 后续仍需 default-nameserver/bootstrap、nameserver-policy、respect-rules、Fake-IP/映射和 IPv6 的真实契约；当前严格子集不能解决订阅 B 的完整 DNS。保留既有 resolver 行为说明：DoH 域名上游 bootstrap 用系统 DNS，多上游答案按内核并集合并，CIDR 过滤触发但 fallback 失败时仍可能返回主答案，未承诺强制拦截。
5. 指纹、Hysteria2 ports/mport/混淆等仍是阻塞项，九种协议的严格子集不代表所有分享链接或 Clash 节点均可用。Dart HttpClient 与 curl 的公网差异仍未定位。用户提供的 A/B 订阅链接不在文档、fixtures 或日志中；若新会话没有可用对话/环境中的真实链接，需要用户重新提供后才能复验，不能自行猜测。

### 实现入口与复现提醒

- 分享 URI：`lib/core/share_link.dart`；DNS：`lib/core/dns_options.dart`、`native/core-host/src/dns.rs`；编译：`lib/core/compiler.dart`（`windows-dns.1`）；宿主能力：`native/core-host/src/lib.rs`。
- 固定内核提交不变；`native/vendor/vp-protocol` 的 P001 与新增 `native/vendor/vp-dns` 的 P002 为选择性补丁。构建 ID 为 `+P001+P002`。来源、变更和测试见 `native/vendor/README.md`，不要修改参考 checkout 来代替正式补丁。
- 当前环境 `python` 指向 WindowsApps 别名，脚本用 `py`：`py tools/verify_host.py --host native/core-host/target/release/flvp-core-host.exe`、`py tools/verify_research.py --docs-only`。
- DNS 回归：`flutter test test/dns_options_test.dart test/dns_runtime_test.dart`；Release 运行测试可在该测试进程设置 `FLVP_TEST_HOST` 为 Release host 的绝对路径。DNS crate 单测用 `cargo test --locked --manifest-path native/vendor/vp-dns/Cargo.toml --lib --target-dir native/core-host/target`；不能从 host workspace 直接 `-p vp-dns` 测其 dev-dependencies。
- 共享 typed schema、宿主或 vendor 改动后同步更新双层校验与测试，并重新构建 Windows；不运行 Android 构建。测试配置/公开 DNS 查询均不能替代真实订阅的完整导入与公网转发验收。

## 17. 增量：GEOIP / GEOSITE 规则与本地 Geo 资源（2026-10-31）

上一段留下的“规则类型尚未支持”是导入硬阻塞：只要订阅里有一条 GEOIP/GEOSITE，整份导入直接失败。本轮把它接通，同时保持“过滤字段/静默跳过”禁令：

1. `lib/core/profile.dart` 新增 `RuleKind.geoIp` / `geoSite`、`GEOIP`/`GEOSITE` 核心类型与类别格式校验；`no-resolve` 同时允许用于 IP 与 GEOIP 规则。
2. `lib/core/configuration_importer.dart` 接受这两种规则，GEOIP 类别统一转大写；`RULE-SET`/`PROCESS-NAME` 等仍显式拒绝。
3. 新增 `lib/core/geo_resources.dart`：下载 `geoip.dat` / `geosite.dat`（默认 Loyalsoldier v2ray-rules-dat 发布包），4 KiB–6 MiB×16 尺寸边界、临时文件原子替换、`meta.json` 记录尺寸/猚256/来源/时间。文件落在 `%APPDATA%\io.flvpcore\flvpcore\geo`，改动 `compiler`/快照事务。
4. `ClientController.importConfiguration` 与 `refreshConfiguration` 在编译前 `ensureFor(profile)`；缺资源且下载失败时导入失败并报错，不写一份假成功。
5. Rust：新增 `native/core-host/src/geo.rs`，只从本地目录读（`FLVP_GEO_DIR` 或 `FLVP_APP_SUPPORT_DIR/geo`），不跟 URL 自行更新；`config.rs` 把 GEOIP/GEOSITE 加入白名单，预检类别存在性（缺库/缺类别直接报错），并把真实数据库传入 `vp_rule::CompileEnv`（之前是 `&None`，内核会静默跳过）。

已知缺口：`RULE-SET` / `rule-providers`、`lazy:true` 与 `load-balance`、DNS `fake-ip`/`respect-rules`/`nameserver-policy`、非 chrome 指纹、Hysteria2 `ports`/`mport`、TUN 全部未动。真实数据验证：Debug 宿主加载真实 geoip.dat / geosite.dat 后，含 GEOIP,CN + GEOSITE,category-ads-all 的配置启动成功；未知类别 GEOIP,ZZ、GEOSITE,__no_such_category__ 均返回 CONFIG_REJECTED。完整 flutter test 61 项通过（6 项 runtime 测试需 Debug 宿主，未启用）。flutter build windows 本轮未完成：设备 shell 的 PATH 无 cmake，VS 装在 D:\building，需 Developer Prompt。

## 18. 增量：RULE-SET / rule-providers（2026-10-31）

背景：真实订阅普遍带 `rule-providers` + `RULE-SET`。曾试过客户端展开成 `DOMAIN-SUFFIX`/`IP-CIDR`，但真实 provider 是十万级条目（Loyalsoldier `reject.txt` 5.6 MB），Profile 规则上限和启动耗时都撑不住，已废弃。

落地方式（内核原生能力 + 本地文件）：

- Dart：`RuleKind.ruleSet`；`ConfigurationImporter` 接受 `RULE-SET`，要求名称在 `rule-providers` 中定义（顶层白名单放开 `rule-providers`）；`RuleProviderStore`（`lib/core/rule_providers.dart`）下载被引用的 provider 原始载荷到 `<support>/providers/`，每份配置一份 `<sourceId>.json`，导入/刷新/激活时发布为 `index.json`；`removeConfiguration` 会清掉该配置的索引与文件。
- 编译器不变：规则就是 `RULE-SET,name,target`，由内核在运行时匹配（`Matcher::RuleSetDomain/Ip/Classical`），不会膨胀到 Profile。
- Rust：`providers.rs` 读索引，把 `rule-providers`（`type: file` + 绝对路径，反斜杠转正斜杠）注入配置文本，交给 vp-app 自己的 `load_providers`；`config.rs` 规则白名单加 `RULE-SET`、字段校验允许 `no-resolve`，预检复用同一份索引。
- 错误语义：缺定义、未知 behavior、`type: file`/`inline`、缺 url、空内容、超 16 MiB、数量超 32 都抛中文 `ConfigurationException`；索引损坏，宿主报 `Rule provider index is not valid JSON`，不静默跳过。

验证：`flutter analyze` 无问题；`flutter test` 71 项；`cargo test --lib` 13 项；`cargo clippy -D warnings` 通过；真实 5.6 MB provider 配置在 Debug 宿主 `ok=true / running`，未知名称 `CONFIG_REJECTED`。

已知限制：`interval` 不自动更新（只在导入/刷新拉取）；不读本地 `path` 型 provider；`proxy-providers`、`sub-rules`、逻辑规则仍未接入。

## 19. 真实订阅兼容性增量（2026-10-31）

- 导入改为逐项降级：顶层字段、节点参数、策略组字段、DNS 子项、规则类型未支持时记录字段级警告并降级，不再整份失败。
- 节点级降级：client-fingerprint 仅 Reality 生效；ws-opts 未知子项忽略；非法或非 ASCII sni 忽略；http/socks5 单边凭据忽略；密码型协议（ss/trojan/hysteria2/anytls）不做用户名成对校验。
- 策略组：未知成员移除、重复成员去重、空组跳过、interval/tolerance/健康 URL 归一化，load-balance/relay 暂不支持时只跳过该组。
- 上限：节点 1024、规则 8192、策略组成员 1024、配置 1 MiB（Dart 与宿主同步）。
- 回归：用户两份自建订阅均 100% 导入并启动成功（51/51、6/6 节点）；详见 docs/verification.md。
- 待办：ipv6、unified-delay、tcp-concurrent、profile 等顶层字段仍未接入；TUN 仍未实现。
## 20. TUN 与管理员协助进程（2026-10-31）

- 新增 native/core-host/src/elevation.rs：`--elevated-serve` 回环 TCP 常驻服务、`%ProgramData%\FLVPcore\{token,endpoint.json}`、hello 令牌鉴权、仅回环对端；未提权启动直接报错退出（实测 exit=1）。
- config.rs：`Tun` 改为赦免式结构（flatten 收集未知键）。内核字段透传，常见但未实现的字段记警告忽略，未知字段报错。`PreparedConfig` 增加 tun_enabled/tun_auto_route/warnings；新增 `Rejected{code,message}`，非提权遇 tun 返回 TUN_REQUIRES_ADMIN。
- lib.rs：capabilities 暴露 tun/elevated/tunHelperPort/tunInstallable；status 携带 tunEnabled/tunAutoRoute/configWarnings；TUN 与系统代理互斥。
- Dart：tun_options.dart（Profile.tun）、configuration_importer 解析、compiler 输出、elevated_host.dart（计划任务安装 + ElevatedHostTransport）、CoreBridge.switchTransport、ClientController.setTun 与启动恢复；设置页 TUN 开关接到真实流程。
- 待办：Wintun 安装器/卸载、宿主级路由与 DNS 事务快照、UI 卸载协助进程、安卓 VpnService。

## 21. TUN 事务与恢复（2026-10-31 补）

- `native/core-host/src/tun_state.rs`：state/tun.json 事务日志，record/clear/recover，Windows 下 route delete 只删本进程持有条目；启动自愈并把结果放进 status.tunRecovery。
- PreparedConfig/Validated 增加 tun_address/tun_netmask（默认 198.18.0.1 / 255.255.0.0），供事务日志与清理使用。
- 宿主在 start/apply 成功与失败回滚、stop 各分支同步事务日志，避免“记录与实际运行不一致”。
- Dart：CoreStatus 增加 tunEnabled/tunRecovery，设置页展示恢复提示并新增卸载协助进程按钮；FlvpDesignStore 提供默认拒绝实现。
- 未做：卸载协助进程后的计划任务清理需提权（已用 RunAs 弹窗）；TUN 下的真实 wintun 转发依赖用户机器实测。
