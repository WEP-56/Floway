# Floway 开发交接（更新于 2026-10-31）

本文是快速接手入口。待办与验收口径以 TODO.md 为准，本文只记录现状、接线方式、坑与下一步。

## 1. 定位与硬约束

- 仓库 WEP-56/Floway（原 FLVPcore），主分支 main，本地目录 D:\FLVPcore。
- vp_core 为冻结只读的历史分支：不删、不回退、不在其上开发、不作为兼容依据。
- 主线定义：Floway 自己的前端资产（lib/ui 与品牌资源）+ FlClash 的运行实现（内核接入、TUN、订阅与配置、外部控制、平台适配）。FlClash 是权威实现，不做防御性设计，也不自行发明架构。
- 平台只做 Windows 与 Android；不引入 macOS/Linux 工程与产物。
- 许可证 GPL-3.0，保留上游版权与来源说明。
- 凭据、token、订阅地址一律不入库、不入提交信息。
- 失败必须可观测（报错与日志能说明问题），不得静默吞掉假装成功。
- 实测与验收由用户本人在本地执行。

## 2. 现状

- 运行基础已从 FlClash v0.9.2（参考检出 7fd417fb，位于 cilent-example\FlClash，已 gitignore，仅供对照）整体纳入主工程：lib、plugins、core、services、assets、arb、shaders、tool、windows、android、test 与根构建文件；Dart 包名已改为 floway。
- 内核源码以子模块形式纳入：core/Clash.Meta，锁定提交 c5062921（即 FlClash v0.9.2 对应的核心提交），.gitmodules 声明 url 与 branch=FlClash。
- 五入口就位：仪表盘 / 代理 / 配置 / 信息 / 设置（lib/ui/nav.dart；桌面与手机壳共用同一份入口表）。
- Windows 构建已验证：flutter build windows --debug 首次 360s、增量约 24s，产物 build\windows\x64\runner\Debug\Floway.exe（同目录含 FlClashCore.exe、FlClashHelperService.exe，名称沿用上游）。
- 工具链：Flutter 3.47.7 / Dart 3.13.5（E:\flutter）、Go（scoop shims）、cargo 1.95、Visual Studio 2022（C++ 桌面工作负载）。

## 3. 接线架构（改动前必读）

界面与上游之间只有一层桥接，位置：lib/ui/backend.dart。

- FlvpBackendBinder：应用启动后读上游权威状态，回推给界面的 FlvpDesignStore，并用 ref.listenManual 持续同步；界面动作经 FlvpBackend 接口转成上游动作。上游是唯一真相。
- 设计页只依赖 FlvpDesignStore，不直接 import 上游 provider；这样预览页与 test/widget_test.dart 不注入后端时仍然可用（因此不要用 ProviderScope 强依赖去改设计页）。
- FlvpBackend 现有方法：setRunning、setSystemProxy、setTunMode、setMode、setCurrentProfile、addProfileFromLink、deleteProfile、updateProfiles。
- store 回推方法：syncRunning、syncShortcuts、syncProfiles。store 内导入/删除/刷新/切换先判断 backend 是否注入，注入则转发上游，否则保持演示行为。
- 已接上游：启动/停止（setupActionProvider.setRunning，状态读 isStartProvider 与 coreStatusProvider）、出站模式（changeMode / patchClashConfigProvider.mode）、系统代理（networkSettingProvider.systemProxy）、TUN（patchClashConfigProvider.tun.enable）、配置列表与当前配置（profilesProvider / currentProfileIdProvider）、配置添加/删除/全部更新（profilesActionProvider）。
- 未接：代理页策略组与节点与测速、配置编辑与自定义工作区、仪表盘概览（流量、连接数、运行时长等）、信息页四类记录、设置页持久化回写。这些位置仍显示设计稿演示数据。

## 4. 上游入口速查

- 内核与状态：isStartProvider、coreStatusProvider、setupActionProvider.setRunning/changeMode、patchClashConfigProvider.mode/tun.enable、networkSettingProvider.systemProxy。
- 配置：profilesProvider、currentProfileIdProvider、profilesActionProvider（putProfile / addProfileFromLink / deleteProfile / updateProfile / autoUpdateProfiles / readCustomImport / importCustomProfile）。
- 代理（待接）：lib/providers/state/proxies.dart、lib/providers/actions/proxies.dart、lib/views/proxies/。
- 仪表盘组件基准：lib/views/dashboard/widgets/（traffic、connection_stats、proxy_groups、intranet_ip、service_status、memory_info、network_takeover、core_status_button）。
- 免责声明：启动弹窗已移除（lib/bootstrap.dart 删掉 import、调用与两个成员，33 行）；lib/views/disclaimer.dart 仍作为工具/关于页的手动入口保留，acceptedDisclaimerVersion 与 disclaimerVersion 为残留设置项。

## 5. 构建与启动（Windows）

1. git submodule update --init --recursive（取内核源码）
2. flutter pub get
3. flutter run -d windows 或 flutter build windows --debug

内核（Go）与管理员协助进程（Rust）由 setup 构建钩子在 flutter build/run 期间自动编译，不需要单独执行；dart setup.dart windows 是打包入口（产出 exe/zip 发行物），内部同样调用 flutter build，日常开发不必先跑。
Android 需要 Android SDK/NDK 与 Go 工具链，本轮未验证。

## 6. 环境与踩坑（血泪部分）

- 设备执行：DeviceInvoke 的 script.shell，cwd=D:\FLVPcore，单次上限 120s。长任务（构建、克隆、推送）必须用 Invoke-CimMethod Win32_Process Create 起独立进程并写日志轮询，否则会在返回时被杀。
- PowerShell 陷阱：$ErrorActionPreference='Stop' 会把 git/flutter 的 stderr 当终结错误，push 与 analyze 必须单独用 'Continue' 调用；单引号 here-string 内不要写 ''x'' 这种双写转义（会原样写进 Dart 源码）；rd 是 Remove-Item 的别名，函数不得同名；$host 是保留变量。文件改写统一用 ReadTextFile / WriteTextFile / ReplaceExact，ReplaceExact 带命中数断言。
- 应用目标名：windows 侧 BINARY_NAME 与 project 均为 Floway。CMake 只在首次配置时把 CMAKE_INSTALL_PREFIX 写成 $<TARGET_FILE_DIR:目标名> 存进缓存，改过应用名后旧缓存会报 No target，必须删掉 build\windows（或 flutter clean）再构建。
- 依赖：必须沿用仓库根的 pubspec.lock。重新解析会把 material_ui 升到高版本，与 material_new_shapes 冲突，产生成片 ambiguous_import。
- 验证闸门：flutter analyze --no-pub lib 与 --no-pub test 必须无问题；flutter test 需要 Go 与内核源码才能生成原生资产。
- 推送：github push 可能因链路问题失败（curl 55 连接重置、HTTP 408、TLS unexpected eof），而 ls-remote 正常；git 配了 http.proxy=http://127.0.0.1:7897；已用 gh auth setup-git 让 gh 接管 github.com 凭据（已登录 WEP-56、含 repo）。推不动时先查代理链路，勿重建提交。

## 7. 提交与推送状态

- 远端 main 目前停在 b88984d（含运行基础、打包名称链、核心子模块、启动接线与配置列表）。
- 本地待推送：2c98413（构建启动文档）、f506fc5（移除启动免责声明）、90966ad（配置页增删改接线）、be16d5c（TODO 进度）。
- 推送命令：git push origin main；工作区应保持干净。

## 8. 下一步（按 TODO.md 批次）

- 批次1（已完成）：运行基础、五入口、启动/停止与模式/系统代理/TUN 接线。
- 批次2（进行中）：配置页添加/删除/全部更新已接；余 PROFILE-13～16 的编辑、源码与覆写、完整自定义工作区；代理页 PROXY-01～10（策略组与节点、切换、测速）未开始。参考 lib/views/profiles/edit.dart 与 lib/views/proxies/。
- 批次3（未开始）：DASH 概览（流量、配置摘要、策略组摘要、连接统计、内网 IP、服务状态、内存、网络接管）与 INFO 四类记录。
- 批次4（未开始）：SET 设置持久化回写与上游入口补齐。
- 批次5（未开始）：平台裁剪、品牌与整体验收。

## 9. 验证约定

- 静态：flutter analyze --no-pub lib、--no-pub test。
- 构建：flutter build windows --debug（改动涉及原生或启动路径时必跑）。
- 运行与 Android 实测：用户本地执行，交付时如实上报未验证项。
- 每完成一项，在 TODO.md 末尾进度节按编号回写状态。