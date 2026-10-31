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

## Windows 分享链接订阅增量（2026-10-30）

新增 HTTP/SOCKS5、VLESS、Trojan、Hysteria2 / hy2 URI 列表及 Base64 入口，实际通过：

1. `flutter analyze` 无问题；完整 `flutter test` 共 58 项通过。新增确定性编译、凭据单次解码、URI/Clash 身份保持、非法列表整体拒绝和错误脱敏检查。
2. `flutter test test/share_link_runtime_test.dart test/native_protocol_contract_test.dart` 3 项通过。新分享链接的 VLESS Reality、VLESS WS、Trojan、Hysteria2 均通过真实 Windows Debug host eager preflight。独立本地 VLESS v0 peer 验证 wire UUID、目标域名及 HTTP 正文；远程 Base64 导入、改名更新、非法刷新保留运行状态、关闭/重启恢复各完成真实转发。
3. `./tools/build_windows.ps1` 构建正式入口 Windows Release 成功；`py tools/verify_host.py --host native/core-host/target/release/flvp-core-host.exe` 原有 12 项真实转发和生命周期检查通过。
4. `py tools/verify_research.py --docs-only` 36 个本地链接及代码围栏检查通过。

没有重新请求用户真实订阅，没有证明完整 Clash DNS/Geo/provider/端口跳跃兼容，也没有证明新 URI 节点的公网互通。未构建 Android，未修改用户系统代理或系统路由。当前环境 `python` 命中 WindowsApps 别名而无输出退出，验证改用已安装的 `py` 启动器完成。

## Windows 订阅 DNS resolver 增量（2026-10-30）

参考 vpn-parser VP-Core 适配器与 FlClash typed DNS，再核对固定 vp_core 的 resolver/普通代理/TUN 路径。范围、差异及补丁见 [DNS 兼容](dns-compatibility.md)。实际通过：

1. `flutter analyze` 无问题，`flutter test` 63 项通过；含 DNS 模型、导入/编译/模式保留、身份/持久化、非法/未知参数与脱敏。
2. Rust 宿主 `cargo test --locked --manifest-path native/core-host/Cargo.toml --lib` 12 项通过；clippy `--all-targets -- -D warnings` 通过。
3. DNS crate `cargo test --locked --manifest-path native/vendor/vp-dns/Cargo.toml --lib --target-dir native/core-host/target`：23 项本地测试通过，4 项公网测试默认忽略；包括新增 P002 DoT 握手总期限。单独加 `live_ -- --ignored` 后 4 项公网测试均通过（AliDNS DoH/DoT、Tencent DoH、Cloudflare/Google DoH，证书验证保持开启）。
4. `test/dns_runtime_test.dart` 的 Debug/Release host 均通过 2 项测试：所有开放 DNS schema 的实际预检，以及独立本地 UDP/TCP DNS 驱动节点 bootstrap/DIRECT、域名/CIDR/NXDOMAIN fallback、非法刷新和宿主独立拒绝保留旧 revision、DoT 停滞约 3 秒后 fallback、重启后的持久化与再次转发。Release 复现时设置进程环境 `FLVP_TEST_HOST` 为 Release host 的绝对路径。
5. `./tools/build_windows.ps1` 正式入口 Release 成功；Release `verify_host.py` 12 项转发/生命周期检查通过。本轮没有修改系统代理/路由/Windows DNS，没有 Android 构建，也未重新下载用户真实订阅。

本轮早先尝试从 host workspace 直接测试依赖 crate，Cargo 因其非 workspace member 拒绝；随后改用该 crate 所在 vendor workspace 的 manifest 完成测试。两份真实订阅仍有未支持的 Geo/Fake-IP/respect-rules/高级传输等字段，不能据此宣称完整导入成功。

## Windows Geo 规则与资源增量（2026-10-31）

在不引入内核自动更新的前提下，接通 Clash `GEOIP` / `GEOSITE` 规则与本地 Geo 资源；两条真实订阅之前卡在这一步。

1. `flutter analyze` 无问题。
2. `flutter test test/geo_rules_test.dart test/configuration_importer_test.dart test/policy_groups_test.dart` 通过，其中新增 4 项（GEOIP 大写归一与编译、非法类别拒绝、资源下载/摘要记录、超小下载拒绝）。
3. Rust 宿主 `cargo test --locked --manifest-path native/core-host/Cargo.toml --lib` 13 项通过，新增 `geo_rules_need_local_databases` 验证缺 geoip.dat / geosite.dat 时直接拒绝而不是静默跳过。

**真实验证补充**：Debug 宿主加载真实 geoip.dat / geosite.dat（Loyalsoldier 发布包）后，含 GEOIP,CN 与 GEOSITE,category-ads-all 的配置启动成功；GEOSITE,__no_such_category__ 与 GEOIP,ZZ 均返回 CONFIG_REJECTED。完整 flutter test 本地 61 项通过（6 项需 Debug 宿主的 runtime 测试本轮未启用）。

**本轮未执行**：flutter build windows（设备 shell 的 PATH 无 cmake，Visual Studio 装在 D:\building，需 Developer Prompt）、Release 产物验收与任何 TUN 验证。

## Windows RULE-SET / rule-providers 增量（2026-10-31）

把 Clash 的 `rule-providers` + `RULE-SET` 接到内核原生实现上，不再把规则集展开成上万条规则。

1. Dart：新增 `RuleKind.ruleSet`（`RULE-SET,name,target`，允许 `no-resolve`）；导入器接受 `RULE-SET`，要求名称在 `rule-providers` 中已定义，顶层白名单同步放开 `rule-providers`；新增 `lib/core/rule_providers.dart` 的 `RuleProviderStore`：按配置把被引用的 provider 原始载荷下载到 `<support>/providers/`，每份配置存 `<sourceId>.json` 索引，导入/刷新/激活时发布为 `index.json`。非 http/https 类型、未知 behavior、缺 url、空内容、超 16 MiB、缺定义一律报错，不静默跳过。
2. Rust：新增 `native/core-host/src/providers.rs`，把索引转换成内核认识的 `rule-providers`（`type: file` + 本地绝对路径）注入配置文本，由 vp-app 自己的 `load_providers` 读取；宿主不联网、也不让内核按 URL 自动更新。`config.rs` 白名单加 `RULE-SET`（3 或 4 字段），预检用同一份索引编译。
3. 验证（2026-10-31，本机 Windows 11 26100）：`flutter analyze` — No issues found；`flutter test` — 71 项通过；`cargo test --lib` — 13 项通过；`cargo clippy -D warnings` — 通过。
4. 真实数据端到端：下载 Loyalsoldier `reject.txt`（5.6 MB、十万级域名）后，Debug 宿主启动含 `RULE-SET,reject,REJECT` 的配置返回 `ok=true / state=running`；`RULE-SET,nothere` 返回 `CONFIG_REJECTED: Strict rule compilation failed: rules[0]: RULE-SET "nothere" 未在 rule-providers 中定义`。
5. 仍不支持：`type: file` / `inline` 的 provider（需读取任意本地路径，客户端侧显式拒绝）、`interval` 定时更新（只在导入/刷新时拉取）、`proxy-providers`、sub-rules、逻辑规则。

## 用户真实订阅回归（2026-10-31）

样本：用户提供的两份自建订阅（地址不入库、不记录），分别为 51 个节点与 6 个节点。

结果：两份均可完整导入并编译，节点无丢失（51/51、6/6）；宿主 start 返回 ok=true、state=running、mixedPort=17890。

剩余字段级警告（不影响导入）：ipv6、unified-delay、tcp-concurrent、profile 尚未接入；client-fingerprint 仅在 Reality 下生效；ws-opts 的 max-early-data / early-data-header-name 暂不支持；非 ASCII 或非法 sni 已被忽略；lazy 按立即测速处理。

验证方式：临时测试脚本读取订阅文本，调用 ConfigurationImporter.parse(warnings)、ConfigCompiler.compile，再把编译结果交给 native/core-host 的 start 操作；脚本与订阅文本仅存放于 .artifacts（已 gitignore），未提交。PowerShell 向宿主管道传递时需设 $OutputEncoding 为 UTF-8，否则非 ASCII 节点名会导致哈希校验失败。
## TUN 与管理员协助进程（2026-10-31）

- 宿主：`native/core-host/src/elevation.rs` 新增管理员协助进程（常驻回环 TCP，端口 38765，令牌来自 `%ProgramData%\FLVPcore\token`）。`flvp-core-host --elevated-serve` 未提权时直接退出并提示“协助进程需要管理员权限”，已实测退出码 1。
- 计划任务模型对齐 FlClash Helper 的用户体验：`schtasks /Create /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "<exe> --elevated-serve"`，首次安装弹一次 UAC，之后开机常驻、应用静默连接。
- 配置：`tun` 顶层字段从“一律拒绝”改为白名单解析。内核支持的 `enable/auto-route/address/netmask/mtu/fake-ip-range/ring-capacity/auto-redirect` 透传；`stack/dns-hijack/auto-detect-interface/strict-route/device/gso/udp-timeout/endpoint-independent-nat` 记字段级警告后忽略；其余未知字段显式报错并指出字段名。
- 非提权宿主收到 `tun.enable=true` 的快照返回 `TUN_REQUIRES_ADMIN`，不会静默降级为普通代理。
- 互斥：TUN 运行中调用 `enableSystemProxy` 返回 `SYSTEM_PROXY_CONFLICT`；`start/apply` 在 TUN 配置下不再恢复系统代理。
- Dart：新增 `TunOptions`（tun_options.dart，随 Profile 序列化）、导入器按字段降级、编译器输出真实 tun 段；`elevated_host.dart` 提供计划任务安装/卸载、令牌读取、`ElevatedHostTransport`（回环 TCP + hello 鉴权）；`ClientController.setTun` 负责切换宿主、重建快照，启动时若上次 TUN 开启会自动重连协助进程，连不上则回退普通代理并提示。
- 校验：`cargo test --lib` 13 项通过（含 tun 白名单、未知字段报错、`TUN_REQUIRES_ADMIN`）；`flutter analyze` 无问题；`flutter test` 80 项通过（新增 test/tun_options_test.dart 4 项）。
- 未完成：Wintun 组件安装与真实流量转发需在用户机器实测；TUN 下的路由/DNS 事务恢复依赖内核 vp-tun 的 auto_route，本轮未额外做宿主级快照；卸载协助进程入口（HelperClient.uninstall）尚未接到 UI。
