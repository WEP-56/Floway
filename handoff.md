# Floway 开发交接（更新于 2026-11-01）

本文是快速接手入口。待办与验收口径以 TODO.md 为准，本文只记录现状、接线方式、坑与下一步。

## 1. 定位与硬约束

- 仓库 WEP-56/Floway（原 FLVPcore），主分支 main，本地目录 D:\FLVPcore。
- vp_core 为冻结只读的历史分支：不删、不回退、不在其上开发、不作为兼容依据。
- 主线定义：Floway 自己的前端资产（lib/ui 与品牌资源）+ FlClash 的运行实现（内核接入、TUN、订阅与配置、外部控制、平台适配）。FlClash 是权威实现，不做防御性设计，也不自行发明架构。
- 命名与存储路径已与 FlClash 完全分开，两者可以同机共存、互不干扰（详见 §2）。
- 平台只做 Windows 与 Android；不引入 macOS/Linux 工程与产物。
- 许可证 GPL-3.0，保留上游版权与来源说明。
- 凭据、token、订阅地址一律不入库、不入提交信息。
- 失败必须可观测（报错与日志能说明问题），不得静默吞掉假装成功。
- 实测与验收由用户本人在本地执行。

## 2. 现状

- 运行基础已从 FlClash v0.9.2（参考检出 7fd417fb，位于 cilent-example\FlClash，已 gitignore，仅供对照）整体纳入主工程：lib、plugins、core、services、assets、arb、shaders、tool、windows、android、test 与根构建文件；Dart 包名已改为 floway。
- 内核源码以子模块形式纳入：core/Clash.Meta，锁定提交 c5062921（即 FlClash v0.9.2 对应的核心提交），.gitmodules 声明 url 与 branch=FlClash。
- 五入口就位：仪表盘 / 代理 / 配置 / 信息 / 设置（lib/ui/nav.dart；桌面与手机壳共用同一份入口表）。
- **命名与存储路径已剥离 FlClash（2026-11-01 完成）**：
  - 内核二进制 FlowayCore、协助服务 FlowayHelperService（Windows 服务名、注册表 `HKLM\SYSTEM\CurrentControlSet\Services\FlowayHelperService\Runtime\Port`、命名管道 `\\.\pipe\FlowayCore_*`、Unix socket `/tmp/FlowaySocket_*`、协议头 `x-floway-helper-protocol`、锁文件 `Floway.lock`）。
  - Android：namespace/applicationId `com.wep56.floway`，包目录 `com/wep56/floway`，`FlowayApplication`，gomobile `-javapkg=com.wep56.floway.core`，深链 `floway://`（保留 clash / clashmeta）。
  - 数据目录 `%APPDATA%\Floway\Floway`（path_provider 取 exe 版本信息的 CompanyName\ProductName；windows/runner/Runner.rc 已改）。
  - 更新源 WEP-56/Floway；调试环境变量 FLOWAY_CORE_DEBUG；安装器进程名与清理项同步。
  - 图标资产已恢复：托盘四态 ico（灰/品牌蓝/TUN 青/安全模式橙）、应用 ico+png、Android 自适应图标（mipmap 前景图 + values-v27/night-v27 splash 指向）。
  - **刻意保留**的上游字样：lib/views/about.dart 的 GPL 归属（Clash.Meta + chen08209/FlClash）、pubspec description、安装器对旧 `com.follow` 目录的清理。
- Windows 构建已验证：flutter build windows --debug 约 20～110s，产物 build\windows\x64\runner\Debug\Floway.exe（同目录 FlowayCore.exe、FlowayHelperService.exe）。运行期 IPC 正常（`[APP] IPC Connected`），服务 Running/Automatic，注册表端口与 Rust 侧一致。
- Android 构建**未验证**：Gradle wrapper 需下载 gradle-9.8.0-all（本地缓存只剩 0 字节 .part），当时用户代理未开、直连 services.gradle.org 超时。开代理后重跑 `flutter build apk --debug` 即可验证包名改动。
- 工具链：Flutter 3.47.7 / Dart 3.13.5（E:\flutter）、Go（scoop shims，go1.27.3）、cargo 1.95、Visual Studio 2022（C++ 桌面工作负载）。

## 3. 接线架构（改动前必读）

界面与上游之间只有一层桥接，位置：lib/ui/backend.dart。

- FlvpBackendBinder：应用启动后读上游权威状态，回推给界面的 FlvpDesignStore，并用 ref.listenManual 持续同步；界面动作经 FlvpBackend 接口转成上游动作。上游是唯一真相。
- **代理页是例外**：lib/ui/pages/nodes_page.dart 已是 ConsumerStatefulWidget，直接 watch `groupsProvider` / `selectedMapProvider` / `delayProvider` / `delayTestPhaseProvider`，直接调 `proxiesActionProvider`。store 里的 nodes / policyGroups / selectedNodeId / selectNode / testNodes 只服务设计预览（simulate:true）。新增页面优先按这个模式写。
- 生产入口以 `FlvpDesignStore(simulate: false)` 构造：无演示流量、无演示时长、累计为 0、`currentNode` 在内核未上报时是 `flvpIdleNode`（未选择节点）。演示基数 `flvpHistoryBase` 只在 simulate:true 时叠加。
- FlvpBackend 方法：setRunning、setSystemProxy、setTunMode、setMode、setCurrentProfile、addProfileFromLink、deleteProfile、updateProfiles、testDelay。
- store 回推方法：syncRunning、syncShortcuts、syncProfiles、syncDelayTesting、syncTraffic（KB/s，含曲线采样，首帧清演示波形）、syncTotals（GB）、syncUptime（秒）、syncCurrentNode。
- 已接上游：启动/停止、出站模式、系统代理、TUN 开关、配置列表与当前配置、配置增删与全部更新、**代理页策略组/节点/切换/单点测速/整体测速**、**仪表盘状态/时长/延迟/订阅/上下行速度与曲线/累计流量/出口 IP 卡片**。
- 未接：配置编辑与自定义工作区、信息页四类记录、设置页持久化回写、仪表盘其余卡片（连接统计、内网 IP、服务状态、内存、网络接管）。

## 4. 上游入口速查

- 内核与状态：isStartProvider、coreStatusProvider、setupActionProvider.setRunning/changeMode、patchClashConfigProvider.mode/tun.enable、networkSettingProvider.systemProxy。
- 配置：profilesProvider、currentProfileIdProvider、profilesActionProvider（putProfile / addProfileFromLink / deleteProfile / updateProfile / autoUpdateProfiles / readCustomImport / importCustomProfile）。
- 代理：groupsProvider（List<Group>，Group 有 type/all/now/testUrl/name）、selectedMapProvider（Map<String,String>）、delayProvider(proxyName:)、delayTestPhaseProvider(proxyName:)、delayTestingGroupsProvider（Set<String>）、proxiesActionProvider（changeProxyDebounce / proxyDelayTest / delayTestGroups / delayTestPageGroup）。
- **延迟语义**：>0 才是真值；`-1` == delayTimedOutValue 表示超时；其他负数表示失败。显示前必须判 `<= 0`，否则会把 -1 当成 1ms 显示成绿色。
- 流量与时长：trafficsProvider（FixedList<Traffic>，字节/秒，取 `[length-1]`）、totalTrafficProvider（Traffic，字节）、runTimeProvider（int?，**毫秒**）、isStartProvider。
- 出口信息：outboundIpProbeProvider（`.watch/.unwatch/.refresh(const [routedOutbound])`，`entryOf(routedOutbound).value` → IpInfo）、ipQualityProvider(ip) → IpQuality（organization / type / level，负数场景见上）。
- 仪表盘组件基准：lib/views/dashboard/widgets/（traffic、connection_stats、proxy_groups、intranet_ip、service_status、memory_info、network_takeover、core_status_button、current_outbound）。
- 免责声明：启动弹窗已移除（lib/bootstrap.dart）；lib/views/disclaimer.dart 仍作为工具/关于页的手动入口保留。

## 5. 构建与启动（Windows）

1. git submodule update --init --recursive（取内核源码）
2. flutter pub get
3. flutter run -d windows 或 flutter build windows --debug

内核（Go）与管理员协助进程（Rust）由 setup 构建钩子在 flutter build/run 期间自动编译（build_config.yaml 的 core_name/helper_name 决定产物名），不需要单独执行；dart setup.dart windows 是打包入口。
改了二进制名之后，build\windows\x64\runner\Debug 里可能残留旧的 FlClashCore.exe / FlClashHelperService.exe，需要手动删；改应用名后若报 No target，删 build\windows 重配。
Android 需要 Android SDK/NDK、Go 工具链与可用的 Gradle 下载链路，本轮未验证。

## 6. 环境与踩坑（血泪部分）

- 设备执行：长任务（构建、克隆、推送）必须放后台作业并轮询，否则会在返回时被杀。
- **PowerShell 批量替换陷阱**：把替换对写成函数并用 `@(@("a","b"))` 传参会**被摊平成两个独立参数**，退化成"首字符→次字符"式的单字符替换，能静默毁掉整个文件（本轮曾把 changelog.dart、request.dart、clash_config.dart、certificate.go 改坏）。批量改名一律用显式 `.Replace` 链或 `[string[]]$from / [string[]]$to` 并行数组，改完用 `git diff --numstat` 核对每处命中数。
- **material_ui 分裂**：Flutter 3.47 把 Material 拆成 package:material_ui。Floway 页面必须 `import 'package:material_ui/material_ui.dart'`；与 flutter/material 混用会抛 `No MaterialLocalizations found.`（本轮统一了 17 个文件）。
- **setState during build**：`ref.listenManual` 里同步 `notifyListeners()` 会撞上 "setState() or markNeedsBuild() called during build"，尤其是 `fireImmediately: true` 和上游在构建期推 groups 的场景。回推 store 一律 `WidgetsBinding.instance.addPostFrameCallback`。
- 布局：Floway 页面挂在壳的 SingleChildScrollView 里，不能用 `Expanded`（用 ConstrainedBox(minHeight:) 撑高）；Scrollbar 与 SingleChildScrollView 必须共用同一个 controller，否则报 "ScrollController has no ScrollPosition attached"。
- FlvpIcon 只有 46 个图标名，未知名会 assert 崩溃（没有 ArrowRight、Waypoints；可用 Route、Network、Zap、Search、X 等），新页面用图标前先查 lib/ui/icons/flvp_icons.dart。
- 依赖：必须沿用仓库根的 pubspec.lock。重新解析会把 material_ui 升到高版本，与 material_new_shapes 冲突，产生成片 ambiguous_import。
- 验证闸门：flutter analyze --no-pub lib 与 --no-pub test 必须无问题；flutter test 需要 Go 与内核源码才能生成原生资产。
- 推送：github push 可能因链路问题失败（curl 55、HTTP 408、TLS unexpected eof），git 配了 http.proxy=http://127.0.0.1:7897，gh 已接管 github.com 凭据。推不动时先查代理链路，勿重建提交。
- UI 自动化：用 Win32 `PrintWindow(hwnd, hdc, 2)` 抓窗口内容不抢焦点；`PostMessage/SendMessage` 发鼠标消息对 Flutter 无效（点不动），需要用户手动点。

## 7. 提交与推送状态

- 本轮提交内容：命名与存储路径剥离 FlClash + 图标资产恢复 + 代理页与仪表盘接上游数据（含出口 IP 卡片、测速反馈、延迟负值语义、演示数据清出生产路径）。
- 推送：git push origin main（远端 https://github.com/WEP-56/Floway.git）。工作区应保持干净。

## 8. 下一步（用户指定顺序）

按 **配置页 → 设置页 → 信息页** 推进：

1. 配置页：PROFILE-13～16 —— 配置编辑、源码与覆写、完整自定义工作区；参考 lib/views/profiles/edit.dart。
2. 设置页：SET 系列 —— 设置项持久化回写与上游入口补齐（当前设置页多数开关只改 store，没有落盘）。
3. 信息页：INFO-03～10 —— 连接/日志/请求/规则四类记录，参考 lib/views/ 下对应视图。
4. 仪表盘其余卡片：连接统计、内网 IP、服务状态、内存、网络接管（DASH 系列）。

已知待办（非本轮）：
- Android 构建验证（需开代理让 Gradle 下载发行包）。
- TUN 实测（helper 与 core 已就绪，尚未在开启连接的状态下验证虚拟网卡与路由）。
- 旧数据目录 `%APPDATA%\com.follow\Floway` 仍在（用户明确不迁移）。

## 9. 验证约定

- 静态：flutter analyze --no-pub lib、--no-pub test。
- 构建：flutter build windows --debug（改动涉及原生或启动路径时必跑）。
- 运行与 Android 实测：用户本地执行，交付时如实上报未验证项。
- 每完成一项，在 TODO.md 末尾进度节按编号回写状态。
