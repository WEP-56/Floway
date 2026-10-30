# M0.1 普通代理客户端实施记录

日期：2026-10-30。目标：在 Windows / Android 打通配置编译、内核通信、真实请求转发和启停回退，作为后续正式客户端开发的基础。当前是开发原型，不是稳定版或完整 VPN 客户端。

后续更新：正式入口已经切换到用户复刻的界面，并通过独立 `FlvpClientStore` 接入真实宿主。本文的节点 / 规则编辑及 JSON 导入导出界面描述属于保留的旧 `ClientShell`，尚未接入新页面。当前入口能力和限制以 [Flutter 接线记录](flutter-client.md) 为准。

## 已实现范围

| 模块 | 当前实现 |
| --- | --- |
| 共享配置 | Dart 严格类型校验、UUID 引用、确定性编译、SHA-256、显式最终 MATCH |
| 上游节点 | 手动添加、编辑、删除、选择无认证 SOCKS5 / HTTP 节点 |
| 分流 | DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、NETWORK、DST-PORT、最终 MATCH；启停、排序、DIRECT / REJECT / PROXY / 节点目标 |
| 配置界面 | 单一活动配置，flvp-profile v1 JSON 粘贴导入 / 复制导出，编译结果预览 |
| 模式 | 规则 / 全局 / 直连，在客户端编译为明确规则；内核统一使用 rule 模式 |
| 本机参数 | 127.0.0.1 混合监听，端口 1024–65535，不开放 LAN |
| 持久化 | 单客户端文件存储、不可变编号快照、pending 日志、运行状态核对后提交 |
| Windows | Flutter → stdin/stdout JSONL 子进程 → 自有 Rust Host → vp_app::App |
| Android | Flutter MethodChannel → 单线程执行器 → JNI → 同一 Rust Host；前台服务持有运行时 |
| 界面 | Material 3；桌面导航栏 / 移动底部导航，真实状态、活动连接和本次累计字节数 |

本轮验收侧重 TCP 普通代理。尚未验收 UDP 数据面、所有规则在复杂网络中的命中行为，也未开放其他上游协议。

设计资产用于布局和风格参考。未接入的订阅、VPN、系统代理等功能没有可操作的虚假开关，页面显示当前能力边界。

## 内核版本与补丁

固定 vp_core v1.1.0：`fa3e7430371930c440ffb1bdccc6869c63554a34`。

所有内部核心依赖固定到该 Git 提交，`native/core-host/Cargo.lock` 锁定第三方依赖。`core-example` 和 `cilent-example` 不参与客户端构建。

真实转发测试发现普通 HTTP 入站把带端口的 authority 当作完整 DNS 主机名。例如 `GET http://127.0.0.1:动态端口/` 会产生 502。项目选择性保留 `native/vendor/vp-protocol`，加入 P001 修复；其余核心 crate 仍来自固定 Git 依赖。构建标识包含 `+P001`。

补丁使用已有 `http::uri::Authority` 解析主机，独立校验显式端口，处理 IPv6 方括号，并拒绝端口溢出和 userinfo。两个回归测试覆盖合法 / 非法 authority。来源及差异见 [vendor 说明](../native/vendor/README.md)。参考 checkout 保持原样。FlClash 仅用于架构调研，没有复制其 GPL 源码。

## 实际通信与状态契约

M0.1 未调用上游 CLI `run`，因此不进入该 CLI 的全局路由清理流程。宿主只管理自身运行时、连接和监听。

协议版本 1：`capabilities`、`status`、`start`、`apply`、`stop`、`quit`。所有写操作带 `expectedGeneration` 和 `expectedAppliedRevision`，拒绝过期状态。Windows 每行一个 UTF-8 JSON 帧，最大 1 MiB；日志走 stderr。Android 通过同一 JSON 请求模型调用 JNI。

启动回执须同时满足 App 报告自身成功绑定监听和真实 SOCKS 握手。`running` 表示本地代理监听已启动，不表示系统流量已被接管、上游节点可达或网络始终健康。

应用配置先完整验证，再停止旧运行时并启动新实例；失败时重建旧快照。该流程会断开活动连接。节点选择也通过编译 / 应用完成，不使用脱离快照的临时选择状态。

Windows 管道 EOF 触发本实例退出；Dart 通信超时会终止自己启动的宿主。Android 的 JNI 调用不在主线程执行；服务采用 START_NOT_STICKY，进程被杀后不会自动连接。Activity / Flutter 控制器脱离不会主动停止服务。通知提供停止操作；Android 13+ 首次启动申请通知权限，拒绝后仍可在应用内停止。

Android 服务的版本标记隔离旧响应和销毁回调，防止其关闭后续启动的实例。这是本地普通代理前台服务，不是 VpnService；没有申请 VPN 接管权限。

## 配置落盘与恢复

客户端私有目录由 `path_provider` 提供，当前存储包括：

```text
state/client.json          活动业务配置和本机参数（同一文件原子替换）
state/pending.json         尚未完成持久化提交的应用操作
state/applied.json         已核对的运行快照指针
runtime/<revision>/        config.json + snapshot.json
staging/<uuid>/            发布前临时目录
```

编译器 `m0.1` 将业务 Profile 转为受限内核 JSON；runtimeHash 对实际配置字节求摘要，logicalHash 排除本机监听端口。快照保存对应 Profile 和本机参数。提交前重新计算字节摘要，并从元数据重新编译核对一致性。

重新接入时若有 pending：内核仍运行则核对实际 revision / hash 并完成对应快照的提交；内核已停止则清理 pending，保持停止。宿主已激活而磁盘提交失败时保留日志和实际运行参数，下次接入可恢复。

这是单一活动配置的原型文件存储，不是设计文档中的完整配置仓库：尚无 SQLite、多进程写入协调、快照清理、备份迁移、订阅资源事务、凭据库或跨设备同步。请只运行一个客户端实例。当前 schemaVersion=1 仅代表受限原型格式，尚未承诺与未来完整 schema 的兼容性。

## 构建与运行

本机验证工具链：Flutter 3.47.7 / Dart 3.13.5、Rust 1.95.0、Visual Studio 2026、Android SDK 36、NDK 28.2.13676358、JDK 17。Android minSdk 26，仅打包 arm64-v8a / x86_64。

从项目根目录执行：

```powershell
# 构建 Rust Release 宿主，并由 CMake 打包到 Flutter 可执行文件旁
./tools/build_windows.ps1

# 默认构建 Android Debug；需预先安装对应 Rust targets 和 NDK
./tools/build_android.ps1
```

Windows 程序：`build/windows/x64/runner/Release/flvpcore.exe`。运行时需保留该目录的 DLL、data 和宿主文件，不能只分发 exe。

Android APK：`build/app/outputs/flutter-apk/app-debug.apk`。这是开发签名 APK；当前未配置正式发布签名。原生库采用 16 KiB LOAD 段对齐，已检查两种 ABI 的 ELF；完整商店发布兼容性仍需独立验收。

Flutter 工程直接位于项目根目录（`pubspec.yaml`、`lib/`、`windows/`、`android/`）。Windows 调试可先运行 `./tools/build_windows.ps1 -SkipFlutter`，再在根目录执行 `flutter run -d windows`。调试宿主也可通过绝对路径环境变量 `FLVP_CORE_HOST` 指定。Android 可先用 `./tools/build_android.ps1 -SkipFlutter` 生成原生库，再在根目录执行 `flutter run -d <设备>`。

## 本轮验证

| 检查 | 结果 / 范围 |
| --- | --- |
| Flutter 单元及组件测试 | 20 项：编译、引用、严格输入、快照篡改、磁盘失败恢复、竞态、节点移除、360 / 1280 宽度页面和节点弹窗 |
| Flutter 静态分析 | 无问题 |
| Rust Host 测试 | 4 项：占用端口、回退、过期请求 / 摘要、禁止 VPN / 未知规则 |
| P001 测试 | 2 项：合法 authority 与非法 / 溢出端口 |
| Rust clippy | Host 全目标 `-D warnings` 通过 |
| Windows 真实转发 | 10 项：能力、HTTP / CONNECT / SOCKS5 入站、HTTP / SOCKS5 上游、失败回退后仍可转发、过期停止、实际流量、EOF 释放端口 |
| Windows 界面集成 | 真实宿主启停、实际 HTTP 请求、端口冲突回退、界面截图 |
| Android 界面集成 | Android 17 x86_64 模拟器：真实 JNI / 前台服务启停、实际 HTTP 请求、端口冲突回退、控制器重新接入同一 generation、界面截图 |
| 构建 | Windows Release / Debug、Android 双 ABI Debug APK 均已构建 |

复现：

```powershell
cargo test --locked --manifest-path native/core-host/Cargo.toml --lib
cargo clippy --locked --manifest-path native/core-host/Cargo.toml --all-targets -- -D warnings
cargo test --locked --manifest-path native/vendor/Cargo.toml -p vp-protocol flvp_p001_tests --target-dir native/core-host/target
python tools/verify_host.py
flutter analyze
flutter test
flutter test integration_test/windows_smoke_test.dart -d windows
flutter test integration_test/windows_smoke_test.dart -d <Android设备>
```

Android 首次运行集成测试需在测试设备上处理通知权限；后续运行可保留安装。集成测试使用临时配置与动态本地端口，结束时停止自己的内核。文件名沿用 windows_smoke_test，但实现按平台选择宿主。

界面截图保存在工作区 `.artifacts/`，属于本地验证产物，不作为源代码提交。

## 下一阶段验收门槛

1. Android 真机：arm64 JNI、通知停止、真实 Activity 重建、熄屏 / 后台 / 系统回收、网络切换、长时间运行。目前验证的是模拟器和 Flutter 控制器重新接入，不能等同真机生命周期验收。
2. Windows：单实例 / 文件写入协调、窗口退出与强制结束、休眠恢复、安装升级。系统代理需加入归属标记和恢复机制后单独接入。
3. 核心适配：Android protect、FD 所有权 / 就绪回执、DNS / FakeIP 一致性；Windows 精确路由安装和归属清理。完成这些后才开放 TUN / VPN。
4. 共享配置：扩展完整 schema、认证与凭据库、订阅和规则资源、迁移 / 备份、快照回收；逐项验证后开放其他协议。
5. 发布前补齐性能、二进制体积、长期稳定性、签名、第三方来源及许可声明。本轮没有产生性能基准或完整协议支持结论。
