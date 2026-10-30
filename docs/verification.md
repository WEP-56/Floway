# 本轮验证记录

执行日期：2026-10-30（Asia/Shanghai）。固定内核提交 `fa3e7430371930c440ffb1bdccc6869c63554a34`。环境 Windows x64 / PowerShell，rustc 1.95.0、cargo 1.95.0；使用上游 Cargo.lock。

## 实际执行

| 项目 | 命令 / 方法 | 结果 |
| --- | --- | --- |
| 版本一致性 | 本地 Git HEAD/tag/status 与 GitHub API main/latest release 核对 | 本地与远端一致，v1.1.0；内核 tracked 文件无改动 |
| 配置与规则 | `cargo test --locked -p vp-config -p vp-rule --lib -- --test-threads=1` | 11 + 29 = 40 项通过 |
| 控制 API | `cargo test --locked -p vp-app --lib api::tests -- --test-threads=1` | 2 项通过；使用 loopback 测试 |
| C ABI | `cargo test --locked -p vp-ffi --lib -- --test-threads=1` | 3 项通过，含普通 mixed 启停/重载/统计与字符串释放 |
| CLI 构建 | `cargo build --locked -p vp-bin` | 成功构建 Windows debug CLI |
| 文档与样例复现脚本 | `python tools/verify_research.py` | 通过；8 个配置校验预期全部符合，21 个文档本地链接及代码围栏检查通过 |
| 平台官方资料 | Android VPN/Builder/FGS/16 KB、Windows Job/Pipe/WinINet、Wintun 页面 | 访问成功；来源见调研末尾 |

共运行 **45 项相关上游单元测试，全部通过**。未运行全部 workspace 测试，不将上游 README 的测试总数当作本轮结果。

## 如何复现

先把固定提交放到 `core-example/vp_core`，保持 tracked 文件无改动，再从项目根执行：

```powershell
python tools/verify_research.py
```

仅检查 Markdown 本地链接和代码围栏：

```powershell
python tools/verify_research.py --docs-only
```

脚本会构建并运行选定 Rust 单元测试、CLI validate，不会调用 `vpcore run`、`clean-routes`，也不会设置系统代理、建立 TUN、修改路由、安装服务。FFI 单测会在普通本机端口短时建立 mixed listener；端口冲突可导致该用例失败，应如实排查。

## 已证明与未证明

1. 已证明此工具链可构建所选 crate，相关单测通过，YAML 样例可以按预期静态校验；这些不足以证明业务功能全部正确。
2. `validate` 不执行完整规则编译或读取 provider/Geo；未知规则/字段以及某些越界数字可以通过。limitations 样例是缺口证据，绝不表示应允许 FLVPcore 应用。
3. FFI 生命周期测试没有注入 Android FD，也没有使用 VpnService/protect；不能外推 Android VPN 已可用。
4. 未执行 Windows TUN、管理员/SCM 服务、系统代理、真实路由恢复、Android 打包/真机、16 KB 页、Doze/always-on/lockdown。
5. 未验证上游发布包字节摘要、全部协议互通、真实性能/内存、跨端同步、迁移或 24 小时稳定性；后续验收矩阵在两端文档列出。

以上为最初调研阶段的验证记录。后续客户端业务模型、编译器、原生宿主和 P001 补丁已经实现；M0.1 验证记录见 [实施记录](m0-implementation.md)，新设计界面的接线范围见 [Flutter 客户端](flutter-client.md)。架构文档中的其他验收要求不应被误读为已通过测试的结果。

## 新设计界面接入真实代理（2026-10-30）

保留设计页面、组件、动效和自定义顶栏，通过独立数据适配器连接真实控制器。实际验证：

1. `flutter analyze`：无问题。
2. `flutter test`：31 项通过；包含新增持久化配置加载、原生启停、失败回退、快速停止、配置并发、销毁期间回调，以及采样时间 / 计数重置 / 累计值测试；原有桌面和移动端设计组件测试仍保留。
3. `python tools/verify_host.py`：10 项通过，覆盖 HTTP / CONNECT / SOCKS5 入站、HTTP / SOCKS5 上游、失败回退后的真实转发、过期请求、流量计数和 EOF 清理。
4. `flutter test integration_test/windows_smoke_test.dart -d windows`：新数据适配器驱动真实 Windows 子进程，HTTP 转发、流量计数、端口冲突回退、模式切换，以及运行中关闭后监听端口释放。
5. 同一集成测试在 `emulator-5580`（Medium_Phone，Android 17 x86_64）通过：真实 JNI / 前台服务、HTTP 转发、配置回退，以及旧控制器销毁后重新接入同一 generation。无人值守测试通过 `adb shell pm grant io.flvpcore.app android.permission.POST_NOTIFICATIONS` 授予测试模拟器通知权限；不代表已复验拒绝通知权限场景。

本轮没有验证真实 Android 手机、VPN/TUN、系统代理、长期后台保活或上游认证协议。统计累计值只在当前客户端进程内保存。

## Windows 系统代理增量（2026-10-30）

本轮实现当前用户 LAN WinINet 接管，能力和边界见 [Windows 文档](bridge-windows.md#6-系统代理与-tun-是两种接管方式)。实际通过：

1. `flutter analyze` 无问题；`flutter test` 32 项通过。新增开关的能力协商、未启动拒绝、真实状态回显，以及失败不报成功的 store 检查。
2. `cargo test --locked --manifest-path native/core-host/Cargo.toml --lib` 8 项通过；`cargo clippy ... --all-targets -- -D warnings` 通过。恢复测试使用可注入后端，覆盖 PAC/WPAD/手动原值、外部冲突、通知失败回滚、部分恢复重试与损坏日志。
3. `python tools/verify_system_proxy.py` 在 Windows 真实 WinINet 上通过：独占锁、未运行拒绝、过期写操作、PAC/WPAD/手动代理恢复、端口变化、apply 失败回滚、stop/EOF 恢复、强杀后独立恢复进程、下次启动恢复、外部修改不覆盖。脚本短暂更改当前用户 LAN 设置，finally 恢复并读回确认原设置；不访问 Internet、不输出原 PAC URL。不要和其他会改变系统代理的测试并发运行。
4. `python tools/verify_host.py --host native/core-host/target/debug/flvp-core-host.exe` 原有 10 项真实转发/生命周期检查通过。
5. `flutter test integration_test/windows_smoke_test.dart -d windows --dart-define=VERIFY_SYSTEM_PROXY=true` 通过，覆盖设计 store → Dart bridge → Rust → WinINet 的真实开启、配置失败回退后保持接管、停止恢复，以及原有转发/流量/退出路径。默认集成测试不启用系统代理，需显式传该参数。

未宣称验收：Android VPN、Windows TUN、Windows 全版本矩阵、同时杀死 UI/Host 后的即时恢复服务、多个自定义数据目录并行接管。用户原系统代理值已恢复；系统代理是当前运行状态，停止后不会下次自动开启。

构建收尾：`tools/build_windows.ps1` 的正式入口 Release 与 `tools/build_android.ps1` 的 arm64-v8a/x86_64 Debug APK 均成功；Android 本轮仅构建验证，未重跑模拟器/真机运行。Release 宿主再次通过 `verify_host.py` 与 `verify_system_proxy.py --host native/core-host/target/release/flvp-core-host.exe`，并读回确认原 WinINet 设置已恢复。

## Windows 配置仓库与仪表盘 TUN 开关（2026-10-30）

按用户要求取消旧数据迁移计划，仅推进 Windows。实现范围与两个真实订阅的脱敏兼容性结论见 [Windows 配置仓库](windows-configurations.md)。本轮 `flutter analyze` 无问题、44 项 Flutter 测试通过，新增 `windows_configuration_test.dart -d windows` 的真实 A/B 上游切换与更新测试通过；TUN 开关仅为入口，不开放原生 TUN。两个用户订阅均已真实下载检查结构，但完整配置及协议认证仍超出本轮导入能力，不计作导入/节点连通成功。


## Windows 协议认证与预检（2026-10-30）

- `flutter analyze` 无问题；`flutter test` 48 项通过，包含九种协议序列化/编译、认证身份、严格拒绝、真实 Windows Debug 宿主契约。
- `cargo test --locked --manifest-path native/core-host/Cargo.toml --lib` 10 项通过，clippy `--all-targets -- -D warnings` 通过。
- `python tools/verify_host.py --host native/core-host/target/debug/flvp-core-host.exe` 12 项通过，含 HTTP Basic 和 SOCKS5 用户认证真实转发。
- `cargo test --locked --manifest-path native/vendor/Cargo.toml -p vp-protocol loopback --target-dir native/core-host/target` 共 22 项通过。上游本地回环不等于公网互通。
- Windows configuration 与 smoke 集成通过；`tools/build_windows.ps1` Release 成功；未构建 Android，未改系统代理设置。
- 用户两份订阅内存探测：完整导入均拒绝；A 单节点校验 41/51、B 8/30；抽样 8 个 listener ready，HTTPS 成功 0/8。完整策略/DNS、指纹/端口跳跃、实际公网连接仍待完成，详见 [能力与探测记录](windows-configurations.md)。


## Windows 策略组增量（2026-10-30）

新增 typed 策略组、基础 Clash 规则/IPv6 CIDR、独立组选择和双层引用图校验。`flutter analyze` 无问题，52 项 Flutter 测试通过（包括实际 Windows host 的分流、故障转移、A→B 和重启保留选择）；Rust 10 项、clippy 与宿主 12 项转发检查通过。`integration_test/windows_policy_test.dart -d windows` 已验证下拉选择驱动真实上游 A→B，截图 `.artifacts/ui/windows-policy-groups.png` 已目视检查，无溢出；界面数据来自本地合成测试。

真实订阅探测新增独立 curl 客户端：A 的 Hysteria、AnyTLS、SS 各一个样本 HTTPS 200 + 正文校验通过，8 个抽样合计 3 个成功。Dart HttpClient 仍 0/8，差异未定位。两个真实订阅完整导入仍未完成，能力边界见 [最新记录](windows-configurations.md)。未做 Android 构建，未修改用户系统代理。
