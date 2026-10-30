# FLVPcore 开发交接

更新：2026-10-30。工作区：`D:\FLVPcore`。本文供新会话直接接续，区分已实现能力、用户已确定的产品方向与待验证的实现方案。

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
