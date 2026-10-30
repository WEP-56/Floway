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
