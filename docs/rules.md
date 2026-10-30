# 全平台统一规则与规则集规范

状态：FLVPcore v1 设计约定；源码基线及 S7–S10 等引用见 [调研](core-research.md)。规则模型跨端共享，进程、包名和系统接管能力按设备验证。

## 1. 规则匹配契约

1. `rules` 有序，第一条命中决定目标；禁止为“优化”自行重排规则。上游相邻同目标规则可能合并，API 展示不保证等于原始行数。
2. 所有启用规则的 target 必须解析到有效节点、组或已验证内置出站；v1 默认只暴露 `DIRECT` 和 `REJECT`。S2 还接受其他内置名字，但接受引用不等于已装配同名出站。
3. 必须有且只有一条顶层最终 `MATCH,target`；其后不允许还有规则。所有用户 prepend/append 都只能插入最终 MATCH 之前。
4. 未知类型、缺资源、不可实现的进程规则不允许默默变成 NeverMatch。FLVPcore 默认严格失败，用户可显式禁用对应规则后再应用。
5. 内核 `global` 与未命中回退有不确定组选择；v1 将业务模式编译成 rule + 显式 MATCH，详见 [配置规范](configuration.md)。不要按日志里的“回落 DIRECT”推断真实行为。

建议排序槽位：`用户置顶规则 → 订阅规则（剔除其最终 MATCH）→ 用户追加规则 → 项目明确选择的最终 MATCH`。内置 LAN/保留网段规则只有产品明确启用时才插入，并展示其优先级；不能把直连例外藏进编译器。

## 2. 上游规则支持范围

“存在解析器”不表示每个入站都填充匹配所需元数据。

| 类型 | 当前实现 | FLVPcore v1 决策 |
| --- | --- | --- |
| DOMAIN | 精确域名 | 支持 |
| DOMAIN-SUFFIX | 根域与子域 | 支持 |
| DOMAIN-KEYWORD | 大小写不敏感子串 | 支持，提示可能宽泛命中 |
| DOMAIN-REGEX | Rust regex 语法 | 按固定构建测试；不假设支持 PCRE lookaround/backreference |
| IP-CIDR / IP-CIDR6 | 目标 IPv4/IPv6 集 | 支持，带 no-resolve 的语义见下文 |
| SRC-IP-CIDR | 来源 IP | 依赖真实 source 可见性 |
| DST-PORT / SRC-PORT | 单端口、`a-b`、`/` 分隔多段 | 支持；端口 1..65535，输入区间顺序严格校验 |
| GEOIP / GEOSITE | 本地库和类别匹配 | 库、类别、feature 都满足才支持；缺失则 error |
| IP-ASN / SRC-IP-ASN | 本地 ASN mmdb，受 geoip feature 约束 | 预检 ASN、源地址及资源；不把文本 AS 列表当数据库 |
| NETWORK | TCP / UDP | 支持，不扩展为任意 L4 类型 |
| PROCESS-NAME | 对 session.process 匹配 | Windows 条件支持；Android v1 不映射为包名 |
| PROCESS-PATH | 同一个进程字符串作路径匹配 | 当前数据源多返回基名，无完整路径保证，v1 默认不启用 |
| IN-NAME / IN-TAG / IN-TYPE | 三者当前都比对 inbound 字符串 | 仅按实测 tag 映射；不能当三个独立维度 |
| IN-USER / IN-PORT | 依赖入站填写 user / port | 限已证明可填充的入站 |
| RULE-SET | domain / ipcidr / classical | 仅支持下表兼容子集 |
| AND / OR / NOT | 括号表达式，递归深度有限 | 用 AST 生成，上游超过 8 层报错，客户端限制总深度不超过 8 |
| SUB-RULE | 条件命中后进入具名子规则表 | 检查引用、循环、深度和目标；保持原序 |
| MATCH | 无条件匹配 | 顶层强制最终一条 |
| 其他 mihomo 扩展 | 部分会告警并 NeverMatch | 默认阻止应用，例如未验证的 RULE-SET 扩展参数、进程正则等 |

域名输入共享层统一处理大小写、尾点和 IDNA（固定实现/版本），保留原始显示值；CIDR 验证前缀和地址族。需要符号或逗号的字段由 AST 序列化，不能用通用 CSV 粗暴拆解复杂规则。

## 3. DNS 与 no-resolve 的精确定义

S9 按规则顺序匹配，只有当前规则需要目标 IP、且上下文尚无目标 IP 时才惰性 DNS 解析；当前取解析结果第一个地址参与规则匹配，不保证对全部 A/AAAA 逐一判断。

`no-resolve` 表示这一条规则**不主动为匹配去解析域名**。如果会话原本是 IP，或前面的规则已触发解析，它仍可匹配现有 IP；它不表示禁止出站拨号时 DNS，也不表示系统 DNS 不会访问网络。

```yaml
rules:
  - DOMAIN-SUFFIX,example.com,PROXY
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - MATCH,PROXY
```

该示例只表达语义；`PROXY` 必须由配置定义成真实组。域名会话若没有现成 IP，不因第二行单独触发解析。第三行是明确后备。

TUN 的 FakeIP 应只承担“假地址 ↔ 原域名”的一致映射，不能让假地址误入真实 GeoIP/ASN 判定。S4/S10 当前存在两套池与 resolver 分离，必须先修复共享映射。节点服务器域名、DoH bootstrap 和 DIRECT DNS 查询也必须走可逃逸 VPN 的底层网络，详见 Android 文档。

## 4. Rule Provider 不是完整 mihomo 规则集

| 项目 | 当前实际行为 | 统一策略 |
| --- | --- | --- |
| format | schema 有 yaml/text/mrs 注释，但 loader 实际只读文本 / payload YAML，未实现 MRS 解码 | v1 接受 text/yaml，拒绝 MRS，不通过改后缀“转换” |
| domain 裸域名 `example.com` | 后缀匹配，含根域与子域 | 为避免误解导出成显式 `+.example.com` |
| `+.x` / `.x` | 当前都包含根域和子域 | 按当前语义固定，跨内核导出提示差异 |
| `domain:x` | 只匹配精确域名 | 支持 |
| `keyword:x` | 域名子串 | 支持 |
| `regexp:x` | 当前忽略 | 严格预检拒绝，不允许“加载成功”掩盖缺失 |
| `*.x` | 没有独立通配符处理分支 | v1 拒绝或经明确无损转换；不得默认认为与 `+.x` 相同 |
| ipcidr | CIDR 行；loader 取首个逗号前部分 | 客户端只接受纯 CIDR，拒绝尾部隐藏语义 |
| classical | DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、IP-CIDR6、DST-PORT | 仅允许此子集；目标统一由 RULE-SET 行决定 |
| classical 其他行 | PROCESS、GEO、SRC、逻辑等被忽略 | 逐行 error，建议提取成主规则 AST |
| YAML payload | 仅 trimmed 文本以 `payload:` 开始时走 YAML，非字符串项被跳过 | 客户端结构化读取并检查全部项，导出标准形式 |

例如 classical 中的 `PROCESS-NAME,chrome.exe` 不能因为主规则支持 PROCESS-NAME 就认定规则集里也支持。通用规则集转换器必须报告每一项不能表示的内容。

推荐输出本地规则集：

```yaml
rule-providers:
  local_domains:
    type: file
    behavior: domain
    format: yaml
    path: /device/private/runtime/42/resources/domains.yaml
    interval: 0
rules:
  - RULE-SET,local_domains,DIRECT
  - MATCH,REJECT
```

路径为占位示意，由宿主生成本机绝对路径；可运行文件使用 [样例](examples/README.md)。资源内容示例：

```yaml
payload:
  - '+.example.org'
  - 'domain:exact.example.net'
```

更新先校验完整新 payload、记录 hash、生成新配置 revision，再应用；禁止原位覆盖正在运行的资源文件。内核 interval=0 且移除 URL，避免后台旧规则复活。

## 5. 逻辑规则与子规则

```yaml
rules:
  - AND,((DOMAIN-SUFFIX,example.com),(NETWORK,TCP)),DIRECT
  - SUB-RULE,(DOMAIN-SUFFIX,internal.example),internal
  - MATCH,REJECT
sub-rules:
  internal:
    - DST-PORT,443,DIRECT
    - MATCH,REJECT
```

子规则不是节点/组，不参与 targetId 的普通出站解析；SUB-RULE 引用 subRuleId。对子规则引用做 DFS，拒绝循环并在生成后计算真实展开深度；NOT 必须恰有一个子条件，AND/OR 不能为空。

UI 的“规则命中解释”要基于 AST 与真实会话上下文。当前 `GET /rules` 只按逗号切原始字符串取 type/payload，复杂逻辑、SUB-RULE、MATCH 都可能展示不完整；它不能作为无损配置导出来源。

## 6. Windows 进程规则与 Android 包规则

| 场景 | 数据可用性 | 处理 |
| --- | --- | --- |
| Windows mixed 本机 TCP | inbound dispatch 会尝试查询进程基名 | 条件支持 PROCESS-NAME，权限不足/进程退出需诊断 |
| Windows TUN | Session::new_tcp/new_udp 会尝试 Windows IPv4 进程表查询 | 条件支持 PROCESS-NAME；需验证虚拟网卡来源匹配、TCP/UDP、权限和时序，不能只测 Matcher |
| Windows 完整路径、IPv6、远端 LAN 流量 | 不具备统一可靠保证 | 不启用 PROCESS-PATH；远端流量不误认成本机进程 |
| Android 包名单 | VpnService.Builder 可决定哪些应用进 VPN | DeviceSettings 的捕获策略，名单变更重建 VPN |
| Android 按包在 DIRECT/代理组之间路由 | 需要 UID 查询/包解析 + session 元数据 | 当前 vp_core 无 JNI 回调链，v1 不支持；作为后续能力 |

“不进入 VPN”意味着应用使用系统网络；`DIRECT` 则仍可能由 VPN 内核解析、连接和计数，两者不等价。不能将 Android 包名单导出为 PROCESS-NAME，也不能在 Windows 把包名当 `.exe`。

跨端专用规则保存 platformScope，不自动抹除。不支持平台上的**已启用规则默认阻止应用**，给出规则 ID 和原因；用户可以显式禁用它并保存本机覆盖。这样备份往返不会悄悄遗失规则含义。

## 7. 统一 RuleSpec 验证流水线

1. 语法：类型、参数数目、括号、CIDR、端口、regex、逻辑深度。
2. 引用：target、组/节点、provider、sub-rule；保留字与循环。
3. 资源：文件 hash、格式、Geo/ASN 数据库与引用类别；缺失阻止应用。
4. 运行上下文：需要的 process/source/inbound 元数据是否能从目标平台和入站获得。
5. 语义：最终 MATCH、MATCH 后不可达规则、显然被前置规则遮蔽的项；遮蔽通常为 warning，不能擅自删除。
6. 用固定版本 vp-rule 编译，再以 fixture 会话验证目标；warning/NeverMatch 必须结构化报告。生产宿主须补充 strict compile，不能只从日志猜测成功。

v1 不承诺完整网络流量的离线模拟。DNS、嗅探、进程权限与实时网络会影响实际结果，规则预览必须显示缺失上下文，不能给出虚假的确定结论。

## 8. 必须共用的验收语料

| 用例 | 输入 | 预期 |
| --- | --- | --- |
| R01 | DOMAIN exact + 子域 | 精确规则不匹配子域；suffix 同时匹配根与子域 |
| R02 | 两条都能匹配的规则 | 第一条获胜，改顺序结果改变 |
| R03 | 域名 + IP-CIDR no-resolve | 该规则不单独触发 DNS；已有 IP 仍可匹配 |
| R04 | GEOSITE/GEOIP/ASN 缺库或缺类别 | 上游可能启动，FLVPcore 必须拒绝应用 |
| R05 | 未知规则 / classical PROCESS / regexp provider / MRS | 不静默忽略，给出准确来源与行号 |
| R06 | 逻辑、NOT、SUB-RULE、循环、超过深度 | 正确目标；不合法时在应用前失败 |
| R07 | 规则未命中或多组 global | 编译器生成显式 MATCH，结果不受 HashMap 顺序影响 |
| R08 | 更新规则集后 reload 失败 / 旧定时器 | 旧有效版本保持可用；旧内容不能回写新 revision |
| R09 | Windows process 缺失、Android 包策略 | 不把未知进程当 DIRECT，不把包名单解释为路由规则 |
| R10 | FakeIP DNS 后 TCP/UDP 请求，A/AAAA、多域名并发 | 映射同源且不串域，不用假 IP 做真实地域判断 |
| R11 | 当前节点/组被订阅删去 | 明确失效引用，按选择策略处置且不静默直连 |
| R12 | Windows → Android → Windows 备份往返 | 原规则、scope、ID 和顺序保留；设备差异有报告 |

当前上游单元测试的实际运行结果见 [验证记录](verification.md)；这些开发验收用例尚未全部实现或执行。
