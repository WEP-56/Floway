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
  - **刻意保留**的上游字样：lib/views/about.dart 的 GPL 归属（Clash.Meta + chen08209/FlClash）、pubspec description。
- **Windows 安装器身份已独立（2026-11-02）**：`windows/packaging/exe/make_config.yaml` 的 `app_id` 换成 Floway 自己的 `403EFA20-8A74-4183-B5EC-1F4B0A16B238`（此前沿用 FLClash 的 `728B3532-C74B-4870-9068-BE70FE12A3E6`，Inno 因此把已装的 FLClash 当成「旧版 Floway」：跳过目录页、复用 FLClash 的安装目录、覆盖它的卸载登记项，卸载时一起清空），`publisher` 改为 Floway；`.iss` 里显式 `DefaultDirName={autopf}\Floway`、`UninstallDisplayName`/`UninstallDisplayIcon`、`CloseApplications=no`（不让 Restart Manager 动隔壁 FLClash）。卸载只清 Floway 自己的 `%APPDATA%`/`%LOCALAPPDATA%` 下 `Floway\Floway` 与早期 `com.follow\Floway`，**不再删 FLClash 的 `com.follow\clash`**。
  - 旧版残留迁移：安装器在 `InitializeSetup` 读旧键 `...\Uninstall\{728B3532-...}_is1`；目录里只有 `Floway.exe` 时把它当默认安装目录（原地升级）并在装完后删掉旧键，目录里同时有 `FlClash.exe` 时只弹提示，不继承目录也不删键。
  - 旧版用户清理顺序：备份 `%APPDATA%\com.follow\clash` → 卸载旧条目（那条记录其实属于 FLClash）→ 重装 FLClash → 装新版 Floway。Floway 数据在 `%APPDATA%\Floway\Floway`，不随安装目录变化。
- **移动端仪表盘改为横向启停条 + 拼图（2026-11-02）**：`lib/ui/pages/dashboard_page.dart` 的 `_MobileDashboard` 去掉大圆盘，换成 76 高的状态条（左电源键：连接时圆角方块、断开时圆形；中状态与节点；右运行时长；整条可点，连接时整条铺主题色）+ 宽窄交替的拼图行：下载 3 / 上传 2 → 延迟 2 / 订阅流量 3 → 出口信息通栏 → 代理模式 2 / 当前节点+累计流量 3。行内等高靠 `IntrinsicHeight`，窄格数字用 `FittedBox(scaleDown)` 防溢出，卡片内用 `Spacer` 吸收多余高度。桌面布局未动。
- Windows 构建已验证：flutter build windows --debug 约 20～110s，产物 build\windows\x64\runner\Debug\Floway.exe（同目录 FlowayCore.exe、FlowayHelperService.exe）。运行期 IPC 正常（`[APP] IPC Connected`），服务 Running/Automatic，注册表端口与 Rust 侧一致。
- **配置页已接上游（2026-11-01）**：列表读 `profilesProvider`/`currentProfileIdProvider`，卡片菜单覆盖编辑/重命名/覆写/同步/运行配置/复制链接/二维码/导出/删除，工具条有更新全部与排序；添加配置拆成链接/文件/二维码/自定义四个上游入口（lib/ui/pages/add_profile_modal.dart，旧的 import_sub_modal.dart 已删除）。编辑、覆写、自定义工作区、运行配置直接打开上游页面（见 §4）。
- **设置页已接上游（2026-11-01）**：一级分组沿用 Floway 卡片，内容全部换成上游字段与页面；开关直接写 `appSettingProvider`/`networkSettingProvider`/`patchClashConfigProvider`，由上游 `configProvider` 监听落盘；复杂项打开 `ThemeView`/`GeneralView`/`NetworkListView`/`DnsView`/`BackupAndRestore` 等（见 §4）。
- **主题已统一到上游（2026-11-01）**：Floway 壳的深浅与色相不再来自 `FlvpDesignStore`，而是 `currentBrightnessProvider` + `genColorSchemeProvider` 的 primary 色相（`flvpLightColorsOfHue` / `flvpDarkColorsOfHue`，支持 `pureBlack`）；侧栏主题按钮改写 `themeSettingProvider.themeMode`。
- **设置二级页（2026-11-01）**：关于、快捷键、按需连接、入站端口与认证、网络设置（含排除域名）、自定义资源、字体与字号、附加规则、脚本、DNS、资源更新、备份与恢复都已按 Floway 版式重写；接入点、用户代理、开发者选项仍是上游页面，经 `FlvpUpstreamPage` 套了 Floway 配色（见 §4）。
- **配置页二/三级页已 Floway 化（2026-11-01）**：编辑（`lib/ui/pages/subscriptions/edit_page.dart`）、覆写（`extend_page.dart` + `profile_rules_page.dart`）、自定义工作区（`custom_page.dart`）、单份配置的 DNS/NTP/嗅探/TUN 覆写（`profile_override_pages.dart`）都换成了 Floway 版式；数据与动作仍全部走上游（`profilesActionProvider`、`profileRulesProvider`、`setupActionProvider`、`customProfileDataProvider`、`proxyGroupsProvider` 等）。自定义工作区里的规则 / 服务提供者 / 拨号代理 / 策略组编辑器仍复用上游页面（含上游表单弹层），只统一了配色。
- **移动端外壳与安卓细节（2026-11-01）**：底栏改悬浮圆角 dock（`mobile_shell.dart`，内容从 dock 下穿过，FAB/snackbar 偏移按 dock 重算），大标题 26 且顶部间距收紧；应用访问控制换成 Floway 页 `settings/access_page.dart` 并补回「发起授权」入口；通知/磁贴/Documents 图标换成 Floway 标识（`tool/make_android_icons.py` 生成，FlClash 的 `ic.xml`/`ic_service.xml` 已删）；安卓隐藏「TUN 接管」「TUN 路由」两段设置（安卓走 VPN 接管）；修复停止后重连显示「未选择节点」（`backend.dart` 在开始运行时补推当前节点）。
  - 坑：`FlvpRipple` 内部是 `Stack`，默认 `topStart`；槽位是紧约束时子内容必须自己包 `Center`，否则贴左不居中。
- **发布流程（2026-11-01）**：`pubspec.yaml` 为 `0.0.1+1`；`.github/workflows/release.yml` 由 `v*` 标签（或手动指定标签）触发，Android APK 与 Windows 安装包并行构建后发布 Release + `SHA256SUMS`；签名四个 Secrets 已写入仓库，keystore 与密码备份在用户文档目录（`secrets.txt`，不入库）。
- **导航容器现状（2026-11-01）**：Windows 用左侧栏（`lib/ui/shells/desktop_shell.dart`），Android 用底部导航（`lib/ui/shells/mobile_shell.dart`）。安卓底栏只放四项（仪表盘/代理/配置/设置），「信息」收进设置页顶部（`FlvpSettingsPage.onNavigate`），`_NavItem` 宽度按可用宽度自适应。目标是统一成「移动端抽屉 + Windows 右侧栏」，见 §8。
- **Android 构建已通过（2026-11-01）**：`flutter build apk --debug --target-platform android-x64` 成功（约 152MB），装到 127.0.0.1:5555 模拟器实测：仪表盘 / 配置 / 设置 / 信息、主题弹层、自定义资源二级页均正常。构建链路上的三处坑（NDK 28 无 libclang、gomobile VCS、Kotlin 增量缓存）见 §6。
- 工具链：Flutter 3.47.7 / Dart 3.13.5（E:\flutter）、Go（scoop shims，go1.27.3）、cargo 1.95、Visual Studio 2022（C++ 桌面工作负载）。

## 3. 接线架构（改动前必读）

界面与上游之间只有一层桥接，位置：lib/ui/backend.dart。

- FlvpBackendBinder：应用启动后读上游权威状态，回推给界面的 FlvpDesignStore，并用 ref.listenManual 持续同步；界面动作经 FlvpBackend 接口转成上游动作。上游是唯一真相。
- **代理页是例外**：lib/ui/pages/nodes_page.dart 已是 ConsumerStatefulWidget，直接 watch `groupsProvider` / `selectedMapProvider` / `delayProvider` / `delayTestPhaseProvider`，直接调 `proxiesActionProvider`。store 里的 nodes / policyGroups / selectedNodeId / selectNode / testNodes 只服务设计预览（simulate:true）。新增页面优先按这个模式写。
- 生产入口以 `FlvpDesignStore(simulate: false)` 构造：无演示流量、无演示时长、累计为 0、`currentNode` 在内核未上报时是 `flvpIdleNode`（未选择节点）。演示基数 `flvpHistoryBase` 只在 simulate:true 时叠加。
- FlvpBackend 方法：setRunning、setSystemProxy、setTunMode、setMode、setCurrentProfile、addProfileFromLink、deleteProfile、updateProfiles、testDelay。
- store 回推方法：syncRunning、syncShortcuts、syncProfiles、syncDelayTesting、syncTraffic（KB/s，含曲线采样，首帧清演示波形）、syncTotals（GB）、syncUptime（秒）、syncCurrentNode。
- 已接上游：启动/停止、出站模式、系统代理、TUN 开关、**配置列表与当前配置、配置增删/同步/全部更新/排序、配置编辑/覆写/自定义工作区/运行配置（均已 Floway 化）、添加配置四入口**、**代理页策略组/节点/切换/单点测速/整体测速**、**仪表盘状态/时长/延迟/订阅/上下行速度与曲线/累计流量/出口 IP 卡片**、**设置页全部开关与上游二级页**、**主题（深浅/色相/纯黑）跟随上游 ThemeProps**、**设置二级页（关于/快捷键/按需连接/入站端口与认证/网络设置/自定义资源）**、**信息页四类记录（连接/请求/DNS/日志，含搜索、详情、关闭连接、清 DNS 缓存、日志导出与捕获开关）**。
- 未接：仪表盘其余卡片（连接统计、内网 IP、服务状态、内存、网络接管）。
- 遗留：设置二级页里 接入点（`AccessView`）/ 用户代理（`UserAgentsView`）/ 开发者（`DeveloperView`）仍是上游页面（经 `FlvpUpstreamPage` 统一了配色，版式还是上游 Material）；自定义工作区里的规则 / 服务提供者 / 拨号代理 / 策略组编辑器仍是上游页面（外壳与概览已 Floway 化）；导航容器待统一成「移动端抽屉 + Windows 右侧栏」（见 §8）。

## 4. 上游入口速查

- 内核与状态：isStartProvider、coreStatusProvider、setupActionProvider.setRunning/changeMode、patchClashConfigProvider.mode/tun.enable、networkSettingProvider.systemProxy。
- 配置：profilesProvider、currentProfileIdProvider、profilesActionProvider（putProfile / addProfileFromLink / addProfilesFromLinks / addProfileFormFile / addProfileFormQrCode / addCustomProfile / updateProfile / updateProfiles / deleteProfile / providerUsers）、isUpdatingProvider(profile.updatingKey)、profileGroupsCountProvider(profileId)。
- 配置二级页（直接 `BaseNavigator.push` 打开，均为上游页面）：views/profiles/edit.dart 的 `EditProfileView`（含 `renameProfile` 辅助）、extend/extend.dart 的 `ExtendView`、custom/custom.dart 的 `CustomProfileView`、preview.dart 的 `PreviewProfileView`、profiles.dart 的 `ReorderableProfilesSheet`、pages/editor.dart 的 `EditorPage`、pages/scan.dart 的 `ScanPage`。
- 代理：groupsProvider（List<Group>，Group 有 type/all/now/testUrl/name）、selectedMapProvider（Map<String,String>）、delayProvider(proxyName:)、delayTestPhaseProvider(proxyName:)、delayTestingGroupsProvider（Set<String>）、proxiesActionProvider（changeProxyDebounce / proxyDelayTest / delayTestGroups / delayTestPageGroup）。
- **延迟语义**：>0 才是真值；`-1` == delayTimedOutValue 表示超时；其他负数表示失败。显示前必须判 `<= 0`，否则会把 -1 当成 1ms 显示成绿色。
- 流量与时长：trafficsProvider（FixedList<Traffic>，字节/秒，取 `[length-1]`）、totalTrafficProvider（Traffic，字节）、runTimeProvider（int?，**毫秒**）、isStartProvider。
- 出口信息：outboundIpProbeProvider（`.watch/.unwatch/.refresh(const [routedOutbound])`，`entryOf(routedOutbound).value` → IpInfo）、ipQualityProvider(ip) → IpQuality（organization / type / level，负数场景见上）。
- 仪表盘组件基准：lib/views/dashboard/widgets/（traffic、connection_stats、proxy_groups、intranet_ip、service_status、memory_info、network_takeover、core_status_button、current_outbound）。
- 设置与主题：appSettingProvider / networkSettingProvider / patchClashConfigProvider / themeSettingProvider（写入即由 `configProvider` 监听落盘）；`currentBrightnessProvider`（深浅）、`genColorSchemeProvider(brightness)`（上游主题色 → Floway 色相）、`delayTestTimeoutOptions`（common/constant.dart）、`defaultPrimaryColors`（主题色色板）。
- 二级页共用件：`lib/ui/widgets/page_scaffold.dart`（`FlvpPageScaffold`、`FlvpPageScope`、`pushFlvpPage`、`showFlvpTextPrompt`、`showFlvpNumberPrompt`、`showFlvpOptionsPrompt`）、`settings_section.dart`（`FlvpSettingsSection/Row/Toggle/Link/Value`）、`upstream_page.dart`（`FlvpUpstreamPage` + `openFlvpUpstreamPage`：把上游 `ThemeData` 的 ColorScheme 换成 Floway token，供尚未重写版式的上游页面使用）。**跳转必须走 `pushFlvpPage` / `openFlvpUpstreamPage`**，不要直接 `BaseNavigator.push` 一个 Floway 页面。
- 已重写的设置二级页：`lib/ui/pages/settings/about_page.dart`、`hotkey_page.dart`（录制仍用上游 `HotKeyRecorder`）、`on_demand_page.dart`、`inbound_page.dart`、`network_page.dart`、`string_list_page.dart`、`custom_resources_page.dart`（不暴露图标集）、`font_page.dart`、`rules_page.dart`、`scripts_page.dart`（编辑复用上游 `EditorPage`）、`dns_page.dart`、`resources_page.dart`、`backup_page.dart`，以及配置页的运行配置 `lib/ui/pages/subscriptions/preview_page.dart`。
- 已重写的配置二级页：`lib/ui/pages/subscriptions/edit_page.dart`（`FlvpProfileEditPage`：名称/地址/age 密钥/自动更新/源文件编辑与上传，校验用上游 `validateProfileName`）、`extend_page.dart`（`FlvpExtendPage`：标准/脚本模式、立即应用）、`profile_rules_page.dart`（`FlvpProfileRulesPage`：附加规则 + 匹配目标 + 全局规则入口）、`custom_page.dart`（`FlvpCustomProfilePage` 外壳与概览、`FlvpCustomMorePage`）、`profile_override_pages.dart`（`FlvpProfileDnsPage` / `NtpPage` / `SnifferPage` / `TunPage`，都是 `FlvpOverridePage` + 上游 `spec`）。
- 规则卡片共用件：`lib/ui/widgets/rule_row.dart` 的 `FlvpRuleRow`（动作徽章 + 内容 + 目标 + 可选编辑/删除/选择），附加规则页与覆写规则页共用。
- 通用覆写渲染器 `lib/ui/pages/settings/override_page.dart` 的 `FlvpOverridePage<K, M>`：吃上游任意 `OverrideSpec`，按 `OverrideField` 子类（Toggle/Options/Number/Text/List）分派成 Floway 行，校验直接用字段自带的 validator。DNS 已用它；后续覆写类页面可复用，不必复制字段映射。
- 设置二级页（`BaseNavigator.push`）：views/theme.dart 的 `ThemeView`、font_family.dart 的 `FontFamilyView`、config/general.dart 的 `GeneralView`、config/network.dart 的 `NetworkListView`、config/dns.dart 的 `DnsView`、config/rules.dart 的 `AddedRulesView`、config/scripts.dart 的 `ScriptsView`、config/on_demand.dart 的 `OnDemandView`、config/custom_resources.dart 的 `CustomResourcesView`、config/user_agents.dart 的 `UserAgentsView`、resources.dart 的 `ResourcesView`、hotkey.dart 的 `HotKeyView`、access.dart 的 `AccessView`、backup_and_restore.dart 的 `BackupAndRestore`、about.dart 的 `AboutView`、developer.dart 的 `DeveloperView`。注意 `TunView`/`SnifferView`/`NtpView` 需要 profileId（单份配置的覆写），全局 TUN 在网络页里。
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
- **二级页作用域（2026-11-01 踩过两次）**：`FlvpThemeScope` / `FlvpStoreScope` / `FlvpModalHost` 都装在壳里（`MaterialApp.home` 之下），而二级页是根 Navigator 上的路由，不在它们的子树里。直接 `FlvpThemeScope.of(context)` 会报 `Null check operator used on a null value`（整页红屏），弹层也会找不到 host。**打开 Floway 页面（含三级页）一律用 `pushFlvpPage`**（lib/ui/widgets/page_scaffold.dart，会重挂主题/store 并自带 `FlvpModalHost`）；打开上游页面用 `openFlvpUpstreamPage`（内部已走 `pushFlvpPage`）。回归测试见 test/ui/settings_page_test.dart 的三条 “secondary pages… / a pushed page… / third level pages…”。
- **品牌图**：关于页用 `assets/branding/floway.png`（真实 logo），不要用 `FlvpAppMark`（代码画的占位标记）。
- **安卓构建（2026-11-01 修好）**：三处坑——① NDK 27+ 不再带 libclang，rquickjs 的 bindgen 靠 `plugins/rust_api/hook/build.dart` 回退到外部 LLVM 并补 `-resource-dir`（`BINDGEN_EXTRA_CLANG_ARGS_<triple>`），要求见 `plugins/rust_api/README.md`；② gomobile 在临时目录 `go build` 会报 `error obtaining VCS status`，`android/core/build.gradle.kts` 已加 `GOFLAGS=-buildvcs=false`；③ Windows 上 Kotlin 增量缓存关不掉会让 `:android_file_picker` 失败，`android/gradle.properties` 已设 `kotlin.incremental=false`。
- **安卓底栏**：只有 4 项（仪表盘/代理/配置/设置），「信息」在设置页顶部（`FlvpSettingsPage.onNavigate` 回调），桌面侧栏仍是 5 项；`_NavItem` 宽度按可用宽度自适应。
- 布局：Floway 页面挂在壳的 SingleChildScrollView 里，不能用 `Expanded`（用 ConstrainedBox(minHeight:) 撑高）；Scrollbar 与 SingleChildScrollView 必须共用同一个 controller，否则报 "ScrollController has no ScrollPosition attached"。
- FlvpIcon 只有 46 个图标名，未知名会 assert 崩溃（没有 ArrowRight、Waypoints；可用 Route、Network、Zap、Search、X 等），新页面用图标前先查 lib/ui/icons/flvp_icons.dart。
- 依赖：必须沿用仓库根的 pubspec.lock。重新解析会把 material_ui 升到高版本，与 material_new_shapes 冲突，产生成片 ambiguous_import。
- 验证闸门：flutter analyze --no-pub lib 与 --no-pub test 必须无问题；flutter test 需要 Go 与内核源码才能生成原生资产。
- 推送：github push 可能因链路问题失败（curl 55、HTTP 408、TLS unexpected eof），git 配了 http.proxy=http://127.0.0.1:7897，gh 已接管 github.com 凭据。推不动时先查代理链路，勿重建提交。
- UI 自动化：用 Win32 `PrintWindow(hwnd, hdc, 2)` 抓窗口内容不抢焦点；`PostMessage/SendMessage` 发鼠标消息对 Flutter 无效（点不动），需要用户手动点。

## 7. 提交与推送状态

- 更早的提交：命名与存储路径剥离 FlClash + 图标资产恢复 + 代理页与仪表盘接上游数据（含出口 IP 卡片、测速反馈、延迟负值语义、演示数据清出生产路径）。
- `06bc75e`：配置页接上游（列表/菜单/工具条/添加配置四入口 + 上游编辑、覆写、自定义工作区、运行配置、排序），`FlvpField.multiline`、Eye/QrCode 图标、`FlvpBackend.updateProfiles` 语义修正。
- `61e7ebb`：安卓构建修复 —— NDK 28 无 libclang 时的 bindgen 回退（含 `-resource-dir`）、gomobile `GOFLAGS=-buildvcs=false`、关闭 `kotlin.incremental`。
- `c6986bc`：设置二级页按 Floway 版式重写（关于/快捷键/按需连接/入站端口与认证/网络设置/自定义资源 + 共用件）、`pushFlvpPage` 修掉二级页与三级页的 null 崩溃、安卓底栏改四项且信息移入设置页。
- 工作区：仅文档（TODO.md、handoff.md）。
- 推送：`git push origin main`（远端 https://github.com/WEP-56/Floway.git）。推送需要本地代理 127.0.0.1:7897，已开。

## 8. 下一步（用户指定顺序）

用户给的剩余清单，按这个顺序做：

1. ~~**信息页接通**（INFO-03～10）~~ **已完成（2026-11-01）**：四类记录全部接上游真实数据，见 §2 与 TODO.md 末尾「信息页接上游」。连接每秒轮询 `coreHandler.getConnections`，请求/DNS/日志读对应 provider；搜索、详情、关闭连接、清除 DNS 缓存、日志导出与「捕获」开关（`appSettingProvider.openLogs`）均接上游原动作。下一批从第 2 项开始。
2. ~~**剩余二/三级页面 Floway 化**~~ **已完成（2026-11-01 三批共 13 个）**：字体与字号、附加规则、脚本、DNS、资源更新、备份与恢复、运行配置，以及配置页的编辑 / 覆写 / 自定义工作区 / 单份 DNS·NTP·嗅探·TUN 覆写（见 TODO.md 末尾三批进度节）。
   - 已就位可复用件：`lib/ui/pages/settings/override_page.dart` 的 `FlvpOverridePage<K, M>` 能直接渲染上游任意 `OverrideSpec`（DNS 与单份配置的 NTP/嗅探/TUN 已用它）；`widgets/page_scaffold.dart` 的 `showFlvpConfirm`、`showFlvpTextPrompt` / `showFlvpNumberPrompt` / `showFlvpOptionsPrompt`，`FlvpPageScaffold.scrollable`（列表页自带滚动时用 false）；`widgets/rule_row.dart` 的 `FlvpRuleRow`。
   - 仍未 Floway 化：自定义工作区里的规则 / 服务提供者 / 拨号代理 / 策略组编辑器（上游页面 + 上游表单弹层），接入点 / 用户代理 / 开发者设置页。
3. **导航容器风格统一**：移动端改成抽屉（drawer），Windows 改成右侧栏，两者配色/图标/分组与页面保持一致；改完同步 `lib/ui/nav.dart` 的入口表与 `settings_page.dart` 里的信息入口（信息回到抽屉/侧栏后，设置页的 `onNavigate` 入口可以保留也可以去掉）。

随后可做：仪表盘其余卡片（连接统计、内网 IP、服务状态、内存、网络接管，DASH 系列）。

发布：`v*` 标签推上去就会跑 `.github/workflows/release.yml`（Android APK + Windows 安装包 + Release）。本地签名打包需要把 `floway-release.jks` 复制到 `android/app/keystore.jks` 并在 `android/local.properties` 补 `keyAlias`/`storePassword`/`keyPassword`（细节见 `C:\Users\14844\Documents\secrets.txt`）。

已知待办（非本轮）：
- TUN 实测（helper 与 core 已就绪，尚未在开启连接的状态下验证虚拟网卡与路由）。
- 旧数据目录 `%APPDATA%\com.follow\Floway` 仍在（用户明确不迁移）。
- 上游自带 `test/lint` 与 `test/widget_test.dart` 的既有失败（Floway 页面用了 CircularProgressIndicator、`FlvpApp` 缺 ProviderScope），未处理。

## 9. 验证约定

- 静态：flutter analyze --no-pub lib、--no-pub test。
- 构建：flutter build windows --debug（改动涉及原生或启动路径时必跑）。
- 运行与 Android 实测：用户本地执行，交付时如实上报未验证项。
- 每完成一项，在 TODO.md 末尾进度节按编号回写状态。
