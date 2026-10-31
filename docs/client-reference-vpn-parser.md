# vpn-parser 参考调研

调研日期：2026-10-30（Asia/Shanghai）。本地参考仓库 `cilent-example/vpn-parser` 指向 `https://github.com/mateo-ki/vpn-parser.git`，工作树干净，`main` 与 `origin/main` 一致。本文依据提交 `4735038e4148165f3c7af8d3280e04df6d27d3b1`（2026-10-30 07:13:06 UTC）和 tag `v1.15.8`（提交 `869689c78863f5cdb2c12cdd91499fc009efcd6d`）核对；远端 `ls-remote` 当日返回同一 HEAD 与 tag。许可证为根目录 MIT，版权 2026 mateo-ki。

## VP-Core 接入形态与版本边界

`Cargo.toml`（vpn-parser）没有 `vp_core` crate 依赖。`src/kernel/mod.rs` 将 VP-Core 声明为一个 `KernelKind`，通过可执行文件名、版本参数和 GitHub 仓库标识管理；`src/kernel/updater.rs` 固定下载 `mateo-ki/vp_core` release tag `v1.0.0`，并按 Windows/Linux/macOS 架构选取发布资产。即当前源码依赖的是**外置 VP-Core v1.0.0 二进制**，不是 vp_core Rust crate 版本或源码提交。`Cargo.lock` 只锁 vpn-parser 自身 Rust 依赖。

真实调用链：`src/proxy/ir/lower.rs` 将业务选项降为内部 `RoutingPlan` → `src/proxy/compiler/vp_core.rs` 基于 Mihomo 编译结果裁剪字段、节点和规则并生成 YAML → `src/proxy/adapter.rs` 设定 `run -c ... -D ...` 与 `validate -c ...` 参数 → `src/proxy/manager.rs` 写入工作目录、校验配置、启动子进程并轮询本机控制器。运行中的配置重载和 TUN 热切换通过 VP-Core Clash 兼容 REST `PUT /configs`，不是 Rust API。代理生命周期由 `tokio::process::Child` 与 manager 管理。

这套适配器**不能证明所有 Mihomo schema 均可无损使用**。`vp_core.rs` 显式删去 Mihomo 专有键，过滤当前不支持的节点/传输，规整 GeoIP/GeoSite 规则、DNS 和 TUN 字段；`kernel/mod.rs` 还会将不兼容节点回退给 Mihomo（若已安装）。这揭示了很实用的方案：先建立有能力声明的中间 RoutingPlan，再按内核编译，并把丢弃/降级变成可诊断结果。FLVPcore 当前严格受限的 Profile → 确定性 JSON 编译 → 宿主白名单校验与快照事务，和这种边界相符；未来订阅导入可复用“解析成规范模型、能力检查、诊断、再发布不可变快照”的顺序，但不能直接复用其宽泛 Clash 兼容假设。

订阅与策略方面，`src/profile.rs` 的 `UnifiedProfile`/`ProfileSource` 保存多个来源、自定义节点及来源级规则/策略组 YAML；`src/db/` 以 SQLite 存储来源、节点和设置，`src/proxy/types.rs` 为运行编译选项持有规则与组片段，`src/proxy/ir/` 再做编译。节点/组选择由 manager 的 Clash 控制 API 完成。它提供了可参考的职责分层，但和 FLVPcore 要求的本地快照、稳定来源 ID、活动来源节点页、逐订阅选择隔离以及失败回滚仍需逐项对齐；不可把 vpn-parser DB schema 直接当成目标数据契约。

## 平台能力核对

| 项目 | 代码证据与可确认结论 | 对 FLVPcore 的借鉴 / 限制 |
| --- | --- | --- |
| Windows 系统代理 | `src/system_proxy/` 与 `src/system_proxy/terminal.rs` 管理 WinINet；代理 manager 保存 `SystemProxySnapshot`、启停及重启时恢复。发布说明包含系统代理与 TUN 切换。 | 可借鉴捕获/恢复快照、避免重启时短暂恢复代理的生命周期思路。需在本项目验证事务持久化、外部修改冲突和崩溃恢复；不能直接照搬其 registry 操作。 |
| Windows TUN | VP-Core 作为独立进程；`src/platform/`、manager 和 `gui/` 处理 Windows 权限交接、提权进程、Wintun 与 TUN 生命周期。`RELEASE_NOTES.md` v1.15.8 记录了 VP-Core Wintun 稳定 GUID 修复。 | 有实际 Windows 实现线索，但进程提权、Wintun DLL 加载和路由治理与 FLVPcore 内嵌 `vp_app::App` 的宿主架构不同。既定 FLVPcore CLI 退出清理路由风险仍成立；不可照抄其子进程方案后假设安全。 |
| Android | 当前仓库无 Android/Gradle/Kotlin/Java 工程文件，无 `VpnService`、JNI、`protect()` 或 Android FD 适配实现。README 声明的桌面发行平台为 Windows/Linux/macOS，源码对 VP-Core release 资产也只枚举这三类。 | 不能把该参考项目作为 Android VPN/TUN 先例。FLVPcore 自己的 `ProxyService` 仅普通前台代理服务；Android VPN 必须按 `docs/bridge-android.md` 独立实现和实测。 |
| TUN 数据面 | vpn-parser 生成 `tun`/Fake-IP 配置并借 VP-Core 内核实现；其自身承担管理与生命周期，并非实现 TUN 包转发数据面。 | 可参考配置语义和控制流程；路由、DNS、逃逸、接口恢复仍须核验各自实现及所有权。 |

仓库任务/文档与发布说明含 VPN/TUN 设计描述，发布说明是作者声明，不单独视作验收证据。本文只确认能够定位的代码链路；未以本机真实节点、外部网络或破坏性路由操作复测该第三方程序。

## 与 FLVPcore 的决定

1. 参考其“宿主与内核独立发布/运行”的边界，但不采用运行时自动更新。长期目标是让自有 Host 通过稳定适配器管理一个**随 FLVPcore 构建/发布、版本由项目固定的 vp_core 运行时**；内核更新由开发与应用发布流程显式升级、回归后交付。用户侧不自行拉取内核，Flutter 业务层不依赖内核内部 API。这样更新内核时主要验证/调整产物封装、配置编译和适配契约，生命周期及平台接管逻辑留在 Host。
2. 这是后续架构目标，不是当前实现：今天的 `native/core-host` 通过 Cargo 固定 Rust crates，并在进程内调用 `vp_app::App`；切换到外置二进制需要重新验证真实 CLI 的退出副作用、ready 语义、配置热应用/回滚、资源路径和子进程崩溃治理。不可只把 `vp_app::App` 替换成 `Command::spawn` 就视为完成解耦。现有固定提交和自有 Host 在迁移及验收通过前继续作为运行基线，已完成 UI 保持不变。
3. 订阅阶段可借鉴中间表示、适配器明确声明能力、配置预检与逐项诊断。仍先建立满足 FLVPcore 三种来源与事务语义的仓库模型，再实现真实 schema fixtures；导入器发现未知关键字段或不支持项必须可见。
4. Windows 系统代理是接下来可独立闭环的功能：以当前用户 WinINet 为范围，先验证本实例监听，记录原值和本实例写入值，再启用；停止只在当前值仍吻合时恢复。需持久化写前意图并在下次启动恢复，不能只依赖进程析构。
5. Android VPN/TUN 和 Windows TUN 仍按各自桥接文档实现，不因 vpn-parser 使用 VP-Core TUN 配置而宣称可用。

## 依据索引

2026-10-30 DNS 接入补充：再次逐项核对 `vp_core.rs`，确认其 DNS 上游增补、policy 删除及 Geo 兜底会改变输入语义；FLVPcore 采取 typed、双层校验的普通代理 resolver 子集，不复制静默删改。另核对 FlClash 的 typed DNS 模型及固定 vp_core 的普通/TUN 路径，依据、差异和运行验收见 [Windows DNS 兼容](dns-compatibility.md)。

- `cilent-example/vpn-parser/Cargo.toml`：包版本 1.15.8、MIT 许可与没有 vp_core crate dependency。
- `cilent-example/vpn-parser/src/kernel/mod.rs`、`src/kernel/updater.rs`：内核种类、release tag 与平台资产。
- `cilent-example/vpn-parser/src/proxy/adapter.rs`、`src/proxy/compiler/vp_core.rs`、`src/proxy/manager.rs`：编译器、CLI、子进程和 REST 调用链。
- `cilent-example/vpn-parser/src/profile.rs`、`src/proxy/ir/`、`src/db/`：配置、订阅和中间模型职责。
- `cilent-example/vpn-parser/src/system_proxy/`、`src/platform/`：Windows 接管相关代码。
- `cilent-example/vpn-parser/RELEASE_NOTES.md`：v1.15.0 引入 VP-Core、v1.15.6 热切换、v1.15.8 Wintun 修复的发布说明。
