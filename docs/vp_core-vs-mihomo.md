# vp_core × mihomo 配置与行为对照

> **定位**：本项目二开的核心参考文档。所有结论以源码 + 运行实测为准，标注 `文件:行号` 便于复核。
>
> | 项 | 值 |
> |---|---|
> | 内核版本 | **v1.3.1** |
> | commit | `31b72fe` |
> | 核对日期 | 2026-10-31 |
> | 核对方法 | 逐文件阅读 `vp-config` / `vp-rule` / `vp-router` / `vp-app` / `vp-tun` / `vp-transport` / `vp-core` / `vp-ffi` 源码；用 `vpcore.exe run` 起真实内核，对 18 个 REST 端点逐一实测；用 curl 制造真实流量观察 `/connections` |
> | 运行环境 | Windows，内核 `target/debug/vpcore.exe`（v1.3.1），测试端口 mixed 17890 / controller 19090 |
>
> **标注约定**：✅ 支持 · ⚠️ 部分支持/行为有差异 · ❌ 不支持 · 🐞 已确认缺陷
>
> **修订记录**
> - `v1.1.0` 初版。当时结论：无 `PATCH /configs`、`mode` 大写只读、`dns.listen` 无效、`auto-route` 只接管 fake-IP 网段、无出站绑卡。
> - `v1.3.1` **本版**。上述五条全部已被上游修正，本文重写。新增 `tailscale`；新增四项实测缺陷。

---

## 0. 结论摘要

**vp_core 是「宽容的 mihomo 子集 + 少量超集」，控制面已接近 Clash 兼容，但有若干实测缺陷。**

六条关键结论：

1. **配置格式基本可以直接吃 mihomo 的。** 顶层字段一一对应，`vp-config/src/model.rs` 全文件 `deny_unknown_fields` 出现 **0 次**——`sniffer:` `profile:` `hosts:` `experimental:` `tunnels:` 等不认识的块被**静默忽略**，不报错。唯一的硬失败点是 `proxies[].type`（未知协议会解析失败）。

2. **`mode` 已可热切。** `PATCH /configs {"mode":"rule|global|direct"}` 免重启换路由，返回 204，且**写回磁盘 YAML**。`GET /configs` 返回**小写** `{"mode":"rule"}`，与 mihomo 一致。

3. **TUN 已是全流量接管。** `auto_route::enable` 除基础网段外，还会加 `0.0.0.0/1` + `128.0.0.0/1` 双半区路由（`vp-tun/src/auto_route.rs:90-127`），并配合**全局出站绑卡**（`BIND_INTERFACE_INDEX` + `IP_UNICAST_IF`，`vp-transport/src/lib.rs:342-412`）防回环。v1.1.0 时代"只能接管 fake-IP 网段"的结论已作废。

4. **DNS 不再是装饰性字段。** `dns.listen` 已被 `parse_dns_listen` 消费（支持 `:53`、纯端口、完整地址），且**无论是否开 TUN 都会起独立 DNS 服务**（`vp-app/src/lib.rs:803-813`）。`enhanced-mode` 与 `dns.fake-ip-range` 也已被消费。

5. **控制面仍有四个实测缺口**：`/logs`、`/memory`、`/providers/rules`、`/group/{name}/delay` 均 404；`/traffic` 的 WebSocket 握手不合规，标准客户端**直接拒连**。

6. **发现四项可复现缺陷**（详见 §14）：WS 握手伪造、`/rules` 的 SUB-RULE payload 被截断、`/connections` 漏记明文 HTTP 转发、`load-balance` round-robin 因双重 `pick()` 而错位。

---

## 1. 顶层配置字段

`vp-config/src/model.rs:133-225`

| 字段 | vp_core | mihomo | 说明 |
|---|---|---|---|
| `mixed-port` | ✅ | ✅ | HTTP+SOCKS5 同端口 |
| `port` / `socks-port` / `redir-port` / `tproxy-port` | ✅ | ✅ | |
| `allow-lan` | ✅ | ✅ | |
| `bind-address` | ✅ | ✅ | 默认 `"default_bind"` |
| `mode` | ✅ `rule`/`global`/`direct` | ✅ | 见 §10.2，**可 PATCH 热切** |
| `log-level` | ✅ | ✅ | |
| `ipv6` | ✅ | ✅ | 顶层 `ipv6` 是唯一生效的 IPv6 开关 |
| `external-controller` / `secret` | ✅ | ✅ | 见 §9.4 |
| `dns` | ✅ | ✅ | 见 §5 |
| `proxies` / `proxy-groups` / `proxy-providers` / `rules` / `rule-providers` | ✅ | ✅ | 见 §2–§4 |
| `tun` | ✅ | ✅ | 见 §6 |
| `geosite-url` / `geoip-url` | ✅ | ⚠️ mihomo 用 `geox-url` | 键名不同 |
| `asn-url` | ✅ 独有 | ❌ | 供 `IP-ASN` 规则 |
| `sub-rules` | ✅ 独有 | ❌ | 供 `SUB-RULE` |
| `listeners` | ✅ 服务端入站 | ⚠️ 同名不同义 | 自建服务器场景 |
| `resource-limits` | ✅ 独有 | ❌ | 连接资源预算 |
| `tuning` | ✅ 独有 | ❌ | 套接字调优 |

### 1.1 严格性

`deny_unknown_fields` **0 次**。未知顶层键、未知 DNS 键、未知节点选项键均被忽略。二开时**不要**在客户端做字段级校验与剥离。

### 1.2 写法归一化

大量字段同时接受 `kebab-case` 与 `snake_case`（`mixed-port`/`mixed_port`、`fake-ip-range`/`fake_ip_range`）。

---

## 2. 代理协议

`model.rs:458-480`（`ProxyKind`）

| `type` | vp_core | mihomo | 备注 |
|---|---|---|---|
| `ss` `ssr` `vmess` `vless` `trojan` `snell` `anytls` `ssh` `mieru` `socks5` `http` `https` `tuic` `hysteria` `hysteria2` `wireguard` `direct` `reject` | ✅ | ✅ | 完全对齐 |
| **`naive`** | ✅ 独有 | ❌ | 反向不兼容 |
| **`brook`** | ✅ 独有 | ❌ | 反向不兼容 |
| **`tailscale`** | ✅ 独有（v1.3.0 新增） | ❌ | 反向不兼容；`model.rs:477` |

> **反向不兼容的影响**：mihomo 客户端的节点编辑 UI、协议图标、分享链接解析都不认识 `naive` / `brook` / `tailscale`。二开要么隐藏，要么自补 UI。

### 2.1 节点公共选项

`model.rs:441-454`（`ProxyCfg`）：`name`、`type`、`udp`、`udp-over-tcp`、`dialer-proxy`/`detour`（链式代理）、`smux`（`enabled`/`protocol`/`max-connections`/`max-streams`）。

> **`interface-name` 仍不支持**（全仓无此配置项）。但 v1.3.1 提供了**全局**出站绑卡，见 §6.3——语义不同，效果等价。

---

## 3. 策略组

`model.rs:1160-1192`（`GroupCfg` / `GroupKind`）

| `type` | vp_core | mihomo |
|---|---|---|
| `select` | ✅ | ✅ |
| `url-test` | ✅ | ✅ |
| `fallback` | ✅ | ✅ |
| `load-balance` | ⚠️ 见 §14.4 缺陷 | ✅ |
| `relay` | ✅ | ✅ |

### 3.1 组字段

| 字段 | vp_core | mihomo |
|---|---|---|
| `name` / `type` / `proxies` / `use` | ✅ | ✅ |
| `url` / `interval` / `tolerance` / `lazy` | ✅ | ✅ |
| `strategy`（`round-robin` / `consistent-hash`） | ✅ | ✅ |
| `disable-udp` | ✅ | ✅ |
| `include-all` / `include-all-proxies` / `include-all-providers` | ❌ | ✅ |
| `filter` / `exclude-filter` / `include-filter` | ❌ | ✅ |
| `expected-status` / `max-failed-times` / `hidden` / `icon` | ❌ | ✅ |

> **对二开的影响**：`include-all-proxies` 缺失，**必须由客户端在生成配置时把所有节点名展开写进 `proxies:`**。FLClash 的 `lib/common/task.dart` 大量逻辑在做这件事，可直接参考。

---

## 4. 规则

规则类型穷举自 `vp-rule/src/lib.rs` 的解析分支。

| 规则类型 | vp_core | mihomo |
|---|---|---|
| `DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` / `DOMAIN-REGEX` | ✅ | ✅ |
| `DOMAIN-WILDCARD` | ❌ | ✅ |
| `GEOSITE` / `GEOIP` | ✅ | ✅ |
| `IP-CIDR` / `IP-CIDR6` / `SRC-IP-CIDR` | ✅ | ✅ |
| `IP-SUFFIX` | ❌ | ✅ |
| `IP-ASN` / `SRC-IP-ASN` | ✅ | ✅ |
| `DST-PORT` / `SRC-PORT` | ✅ | ✅ |
| `PROCESS-NAME` / `PROCESS-PATH` | ✅ | ✅ |
| `PROCESS-NAME-REGEX` / `PROCESS-PATH-REGEX` / `UID` | ❌ | ✅ |
| `NETWORK` | ✅ | ✅ |
| `RULE-SET` | ✅ | ✅ |
| `SUB-RULE` | ✅ 独有 | ❌ |
| `AND` / `OR` / `NOT` | ✅ | ✅ |
| `MATCH` | ✅ | ✅ |
| `IN-NAME` / `IN-TAG` / `IN-TYPE` / `IN-PORT` / `IN-USER` | ✅ | ⚠️ 部分 |

**修饰符**：`no-resolve` ✅；多值 payload 逗号分隔 ✅。

**语义**：顺序匹配、首个命中生效、`MATCH` 兜底——与 mihomo 一致。

> ⚠️ **实测差异**：命中 `SUB-RULE` 时，`/connections` 里记录的是**子规则本身**（如 `"rule":"DOMAIN"`），看不到 `SUB-RULE` 这一层。
> 🐞 `/rules` 端点会把 `SUB-RULE` 的 payload 截断成 `"(NETWORK"`，见 §14.2。

---

## 5. DNS

`vp-config/src/model.rs:383-425`

| 字段 | vp_core | mihomo | 生效性 |
|---|---|---|---|
| `enable` | ✅ | ✅ | ✅ 消费 |
| `listen` | ✅ | ✅ | ✅ **v1.3.0 起消费** |
| `ipv6` | ✅ | ✅ | ❌ **未消费**，只有顶层 `ipv6` 生效 |
| `enhanced-mode` | ✅ `redir-host`/`fake-ip` | ✅ 另支持 `normal` | ✅ **v1.3.0 起消费** |
| `nameserver` | ✅ | ✅ | ✅ |
| `default-nameserver` | ✅ | ✅ | ❌ **未消费** |
| `fallback` | ✅ | ✅ | ✅ |
| `fake-ip-range` | ✅ | ✅ | ✅ 消费（TUN 未开时作为 DNS 池来源） |
| `fake-ip-filter` | ✅ | ✅ | ✅ |
| `nameserver-policy` | ✅ `HashMap<String,Value>` | ✅ | ✅ |
| `fallback-filter` | ✅ | ✅ | ✅ |
| `respect-rules` / `proxy-server-nameserver` / `fake-ip-filter-mode` / `cache-algorithm` / `prefer-h3` / `use-hosts` | ❌ | ✅ | — |

### 5.1 独立 DNS 服务（v1.3.0 新增能力）

`vp-app/src/lib.rs:803-813`：**无论是否开 TUN**，只要配置了 `dns.listen`，内核就会起一个独立 DNS 服务，提供 fake-IP 与分流解析。

```yaml
dns:
  enable: true
  listen: 127.0.0.1:53     # 支持 ":53" / "53" / "1.2.3.4:53"
  enhanced-mode: fake-ip
```

`parse_dns_listen`（`vp-app/src/lib.rs:121-144`）接受完整 `SocketAddr`、`:port`、纯端口三种写法，缺省地址取 `bind-address`。

**对二开的意义**：不再必须靠 TUN 才能用 fake-IP；可以只做 DNS 接管 + 系统代理，或在 TUN 模式下复用同一套。

### 5.2 其他关键行为

- TUN 启动时另起一个 fake-IP DNS 服务器，`dns_hijack` 在 `TunConfig` 里硬编码 `true`，数据面对进入 TUN 的 UDP:53 直接作答。
- DNS 服务器绑定失败只 `warn!`，不阻断启动。
- **`vp_core` 自己不改系统 DNS**，那是客户端责任（见 §6.4）。

---

## 6. TUN

`vp-config/src/model.rs:305-380`（`TunCfg`）

| 字段 | vp_core | 默认值 | mihomo |
|---|---|---|---|
| `enable` | ✅ | — | ✅ |
| `address` / `netmask` | ✅ | `198.18.0.1` / `255.255.0.0` | ✅ |
| `mtu` | ✅ | **9000**（`model.rs:362-364`） | ✅ |
| `fake-ip-range` | ✅ | `198.18.0.0/16` | ✅ |
| `auto-route` | ✅ | `false` | ✅ 语义已对齐，见 §6.2 |
| `ring-capacity` | ✅ 独有 | 4MB | ❌ |
| `fd` | ✅ 独有 | — | ❌ |
| `stack` | ❌ | 固定 `ipstack` | ✅ |
| `dns-hijack` | ❌ 硬编码 true | — | ✅ |
| `route-address` / `route-exclude-address` / `strict-route` | ❌ | — | ✅ |
| `auto-detect-interface` | ❌ | — | ✅（vp_core 自动做，见 §6.3） |
| `auto-redirect` | ✅ 字段存在但**未消费** | — | ✅ |

> **`mtu` 默认 9000 而非 1500**。示例配置注释里的 1500 只是示例值。若对端不支持巨帧需显式写 `mtu: 1500`。

### 6.1 实现路径

`vp-app/src/lib.rs:155-230`（`start_tun_runtime`）→ `vp-tun` `start_with_handle` → `create_tun_device`（`tun` 0.8.14 + `wintun-bindings`）。Windows 侧注入了**固定静态设备 GUID**（v1.2.0 修复），避免网卡名称序号递增。

TUN 启动失败在 `App::assemble` 里只 `warn!` 不传播，宿主必须自查 `app.tun_runtime`。

### 6.2 `auto-route` 现在是全流量接管

`vp-tun/src/auto_route.rs:51-127`：

```
# 1. 基础网段
route add 198.18.0.0 mask 255.255.0.0 198.18.0.1 metric 1
# 2. 双 /1 拆分路由（比 /0 更精确，不破坏原默认网关）
route add 0.0.0.0   mask 128.0.0.0 <tun> metric 1
route add 128.0.0.0 mask 128.0.0.0 <tun> metric 1
```

`AutoRouteGuard` 在 Drop 时删除上述三条路由；`clean_all_routes()` 同样会清残留。

**所以 TUN 模式下直连 IP 的流量也会进隧道**，不再只限 fake-IP 网段。

### 6.3 出站绑卡（防回环）

`vp-transport/src/lib.rs:342-412`：

- `BIND_INTERFACE_INDEX: AtomicU32` 全局网卡索引。
- `detect_default_physical_interface()`：Windows 下走 `GetIpForwardTable` 找默认路由对应的**物理**网卡（明确排除 `vpcore-tun` 自身）。
- 出站 TCP/UDP 套接字设置 `IP_UNICAST_IF` / `IPV6_UNICAST_IF`；回环地址不绑。
- 同时把索引下推给 `vp_dns`（`set_bind_interface_index`），DNS 上游也走物理网卡。
- TUN 开启时设置（`vp-app/src/lib.rs:210-215`），`TunRuntime::shutdown` 与 `Drop` 时清零。

**这与 mihomo 的 `auto-detect-interface` 等价**，只是粒度是全局而非 per-outbound（mihomo 的 `interface-name` 可按节点指定）。

### 6.4 DNS 接管责任链

```
方案 A（推荐，不依赖路由）：
  客户端把物理网卡 DNS → 127.0.0.1
    → 内核 dns.listen 或 TUN 的 0.0.0.0:53 作答
      → 返回 fake-IP（198.18.x.x）或真实 IP
        → 命中 0.0.0.0/1 路由 → 进入 TUN → 代理

方案 B（依赖路由）：
  保持系统 DNS 不变 → 查询被双 /1 路由导入 TUN → 数据面 UDP:53 劫持作答
```

方案 B 在 v1.3.1 下已经可行（全流量路由 + 出站绑卡），客户端不必改系统 DNS。但方案 A 更稳、可观测、易回滚。

---

## 7. mihomo 有而 vp_core 没有的配置块

已用脚本逐个核对 `model.rs`，以下键**全部不存在**：

| 块 | 影响 |
|---|---|
| `sniffer` | ❌ 无配置项。内核有 `sniff_stream`（`vp-core/src/sniff.rs:201`）但属固定行为。UI 上的"域名嗅探开关"无对应物。 |
| `profile` | ❌ 无 `store-selected`。**用户选的节点不会被内核持久化**，客户端必须自己存。 |
| `hosts` | ❌ |
| `experimental` | ❌ |
| `tunnels` | ❌ |
| `iptables` | ❌ |
| `script` 模式 | ❌ `mode` 只有 rule/global/direct。 |
| `interface-name` / `routing-mark` | ❌ 但见 §6.3，全局绑卡已覆盖主要场景。 |
| `global-client-fingerprint` | ❌ |
| `unified-delay` / `tcp-concurrent` / `find-process-mode` | ❌ 但 `/connections` 已能给出 `process` 字段（见 §9.3）。 |
| `authentication` / `skip-auth-prefixes` / `lan-allowed-ips` | ❌ 控制器只有 `secret`。 |
| `geodata-mode` / `geo-auto-update` / `geox-url` | ❌ 改为 `geosite-url` / `geoip-url` / `asn-url`。 |

> 未知键被静默忽略，出现在订阅里**不会报错**，只是不生效。

---

## 8. vp_core 独有扩展

| 项 | 位置 | 用途 |
|---|---|---|
| `naive` / `brook` / `tailscale` | `model.rs:469,467,477` | 反向不兼容点 |
| `sub-rules` + `SUB-RULE` | `model.rs:197` | 规则集分组复用 |
| `IP-ASN` / `SRC-IP-ASN` + `asn-url` | `vp-rule/src/asn.rs` | ASN 分流 |
| `IN-NAME` / `IN-TAG` / `IN-TYPE` / `IN-USER` | `vp-rule/src/lib.rs` | 入站维度分流 |
| `resource-limits` | `model.rs:227` | 连接资源预算 |
| `tuning` | `model.rs:249` | 套接字调优 |
| `ring-capacity` | `TunCfg` | Wintun 内存优化 |
| `listeners` | `model.rs:267` | 服务端入站 |
| 独立 DNS 服务（不依赖 TUN） | `vp-app/src/lib.rs:803` | 见 §5.1 |

---

## 9. REST API（`external-controller` + `secret`）

实现：`vp-app/src/api.rs`，手写 HTTP 服务，无框架依赖。**18 条路由分支**，已全部实测。

### 9.1 端点清单

| 端点 | 方法 | 实测 | 响应/语义 | 位置 |
|---|---|---|---|---|
| `/version` | GET | ✅ 200 | `{"meta":true,"premium":false,"version":"1.3.1"}` | `api.rs:205` |
| `/proxies` | GET | ✅ 200 | `{"proxies":{name:{name,type,now,all,alive?,history?}}}` | `api.rs:216` |
| `/proxies/{name}` | GET | ✅ 200 | 单个组/节点 | `api.rs:254` |
| `/proxies/{name}` | PUT | ✅ 204 | 选节点，body `{"name":"…"}` | `api.rs:283` |
| `/proxies/{name}/delay` | GET | ✅ 200 / 408 | 见 §9.2 | `api.rs:313` |
| `/rules` | GET | ✅ 200 | `{"rules":[{type,payload,proxy}]}` | `api.rs:345` |
| `/connections` | GET | ⚠️ 见 §9.3 | Clash 标准字段 | `api.rs:357` |
| `/connections/{id}` | GET / DELETE | ✅ | | `api.rs:428,413` |
| `/connections` | DELETE | ✅ | 全断 | `api.rs:423` |
| `/configs` | GET | ✅ 200 | `{"mode":"rule"}` **小写** | `api.rs:447-454` |
| **`/configs`** | **PATCH** | ✅ 204 | **`{"mode":"rule\|global\|direct"}` 免停热切 + 写回 YAML**；非法值 400 | `api.rs:456-504` |
| `/configs` | PUT | ✅ 204 | 全量热重载，`?path=` 或 body `{"path":…}`；失败 500 | `api.rs:505` |
| `/providers/proxies` | GET | ✅ 200 | 无 provider 时 `{"providers":{}}` | `api.rs:570` |
| `/providers/proxies/{name}` | GET | ✅ | | `api.rs:622` |
| `/providers/proxies/{name}` | PUT | ✅ | 更新 provider | `api.rs:676` |
| `/dns/flush` | POST / PUT | ✅ | | `api.rs:706` |
| `/traffic` | GET (WS) | 🐞 见 §14.1 | 每秒推 `{"up":…,"down":…}` | `api.rs:715` |

**实测证据**（`PATCH` 热切 + 写回磁盘）：

```
PATCH /configs {"mode":"global"} → 204
GET   /configs                   → {"mode":"global"}
配置文件 config2.yaml            → mode: global        ← 已写回
PATCH /configs {"mode":"bogus"}  → 400 {"message":"无效的配置 PATCH 请求体或不支持的模式"}
```

### 9.2 `/proxies/{name}/delay` 的真实语义 ⚠️

`api.rs:313-344`：**只对「组」有效**，对单个节点返回 404。

- `url` 缺省为 `http://www.gstatic.com/generate_204`
- `member` 指定测哪个成员；不指定则测该组当前选中项
- 成功 `200 {"delay":ms,"url":…}`；失败 `408 {"message":"测速失败"}`

**要给单个节点测速，必须挂在某个组上并用 `?member=<节点名>`**：

```
GET /proxies/PROXY/delay?member=DIRECT&url=http://127.0.0.1:18080/
→ 200 {"delay":86,"url":"http://127.0.0.1:18080/"}

GET /proxies/node-a/delay?...     → 404 {"message":"not found"}
GET /group/PROXY/delay            → 404 {"message":"not found"}
```

### 9.3 `/connections` 的实际覆盖 ⚠️

实测：**只有 CONNECT 隧道与 SOCKS5 会登记连接，明文 HTTP 转发不会。**

```
明文 HTTP 转发（curl -x … http://…）      → /connections 全程为空
CONNECT 隧道（curl -x … -p http://…）     → 有记录
SOCKS5（curl --socks5 …）                 → 有记录
```

记录的字段（实测原文）：

```json
{"chains":["PROXY","DIRECT"],"download":0,"upload":83,"id":"6",
 "metadata":{"destinationIP":"","destinationPort":"18080","host":"localhost",
             "network":"tcp","process":"curl.exe","source":"127.0.0.1:65140","type":"mixed"},
 "rule":"DOMAIN","rulePayload":"localhost,PROXY",
 "start":"2026-10-31T09:21:46.797Z"}
```

要点：

- `metadata.process` **有值**（`curl.exe`），Windows 下无需额外配置。
- `metadata.destinationIP` 为空（域名场景）。
- `rule` 是**大写**规则类型（`"DOMAIN"`），mihomo 用 `"Domain"`。
- `rulePayload` **包含 target**（`"localhost,PROXY"`），mihomo 只放 payload。
- `chains` **会折叠嵌套组**：`LB → G1 → DIRECT` 只显示 `["LB","DIRECT"]`。

### 9.4 缺失端点（实测 404）

| 端点 | 影响 |
|---|---|
| `/logs` (WS) | 无实时日志，面板"日志"页不可用 |
| `/memory` | 无内存面板 |
| `/providers/rules` | 规则 provider 无法查看/更新 |
| `/group/{name}/delay` | 整组测速需自己并发调 `?member=` |
| `/cache/fakeip/flush` | 无法刷 fake-IP 缓存 |
| `/ui` | 无内置面板 |
| `/restart` / `/upgrade` | 无 |

### 9.5 绑定地址（安全）

`vp-app/src/lib.rs:776`：`TcpListener::bind(&addr)` **直接用配置值，不强制 localhost**。

- 必须显式写 `external-controller: 127.0.0.1:9090`。
- `secret` 为空时**无鉴权**。

---

## 10. 行为差异清单

### 10.1 未知键静默忽略

`model.rs` 无 `deny_unknown_fields`。订阅可直接喂。

### 10.2 `mode` 可热切（v1.2.0+）

`PATCH /configs` 走 `clone_with_mode` + `RouterHandle::swap` 原子换路由，并正则写回 YAML。`GET /configs` 返回小写。

> ⚠️ 实测：`mode: global` 走的是 `global_outbound`（**第一个定义的组**），而不是 mihomo 那种包含全部节点的 `GLOBAL` 选择器。
> 实测 chains：`rule → ["PROXY","DIRECT"]`、`global → ["G1","DIRECT"]`、`direct → ["DIRECT"]`。

### 10.3 无 `profile.store-selected`

节点选择不持久化。客户端自己存，启动时 `PUT /proxies/{name}` 恢复。

### 10.4 无 `sniffer` 配置

`vp-core/src/sniff.rs:201` 的 `sniff_stream` 是固定行为。

### 10.5 TUN 全流量 + 自动绑卡

见 §6.2 / §6.3。

### 10.6 TUN 失败不传播

`App::assemble` 只 `warn!`，宿主必须自查 `app.tun_runtime`。

### 10.7 DNS 服务器绑定失败不阻断

只 `warn!`。53 端口被占用时 TUN 仍显示成功但解析不可用。

### 10.8 `vp_core` 不改系统 DNS / 系统代理

全部客户端责任。

### 10.9 协议超集导致反向不兼容

`naive` / `brook` / `tailscale`。

### 10.10 无 `include-all-proxies`

客户端必须自行展开节点列表。

### 10.11 仍未被消费的字段

- `dns.ipv6`——只有顶层 `ipv6` 生效
- `dns.default-nameserver`——无引导解析实现
- `tun.auto-redirect`——字段存在（`model.rs:325`），全仓无消费点

v1.1.0 里那批装饰性字段中，`enhanced-mode` / `listen` / `fake-ip-range` 已在 v1.3.0 修复。

### 10.12 `TunCfg` 两个默认值来源不一致

`auto_route` 的 serde 默认是 `default_true`（`model.rs:322`，即 `true`），而 `impl Default for TunCfg` 里写的是 `false`（`model.rs:342`）。同一个类型经两条路径构造会得到不同结果。`enable` 两处都是 `true`，没有这个问题。

---

## 11. FFI / 移动端

`vp-ffi` 导出 `extern "C"`：

| 函数 | 用途 |
|---|---|
| `vp_init_logger(log_level)` | 初始化日志 |
| `vp_validate_config(config_str)` | 校验配置，返回 JSON |
| `vp_start(config_str, tun_fd)` | 启动，`tun_fd` 由 VpnService / NetworkExtension 注入 |
| `vp_stop()` | 停止 |
| `vp_reload(config_str)` | 热重载 |
| `vp_is_running()` | 状态 |
| `vp_get_stats(up*, down*)` | 流量统计 |
| `vp_last_error()` / `vp_free_string(s)` / `vp_version()` | 辅助 |

`App::start_with_tun_fd`（`vp-app/src/lib.rs:214`）为 fd 注入入口；`fd` 分支在 `#[cfg(unix)]` 下，Windows 走 Wintun。

---

## 12. 二开影响清单

### 12.1 必须客户端自己实现

| 项 | 说明 |
|---|---|
| 节点选择持久化 | 无 `store-selected` |
| 配置生成 | `include-all-proxies` 缺失，需展开节点列表 |
| 系统代理接管 | 内核不管 |
| 系统 DNS 接管 | 内核不管（但已可选：`dns.listen` + 系统 DNS 指向它） |
| 提权与进程生命周期 | 内核不管 |
| 崩溃自愈 | 路由表、系统代理、系统 DNS 的恢复 |
| 日志 | 无 `/logs`，需从内核 stdout 抓 |
| 整组测速 | 无 `/group/{name}/delay`，需并发调 `/proxies/{group}/delay?member=` |
| 订阅解析 / 分享链接 | 内核只吃最终配置 |

### 12.2 必须改造的 UI 入口

| 面板功能 | 处理方式 |
|---|---|
| 模式切换 | ✅ 可用，`PATCH /configs`（v1.2.0+） |
| 实时流量曲线 | 🐞 `/traffic` 握手不合规，需宽松 WS 客户端或等上游修复 |
| 实时日志 | ❌ 无端点，只能读 stdout |
| 内存占用 | ❌ 无端点 |
| 规则 provider 管理 | ❌ 无端点 |
| fake-IP 缓存刷新 | ❌ 无端点 |
| 节点取消固定 | ❌ 无 `DELETE /proxies/{name}` |
| 连接列表 | ⚠️ 仅 CONNECT/SOCKS5 可见 |
| 负载均衡 | 🐞 见 §14.4，2 成员时几乎不可用 |
| naive / brook / tailscale 编辑 | 反向不兼容 mihomo 生态 |

### 12.3 建议向内核提的接口（按优先级）

1. 🐞 修复 `/traffic` 的 `Sec-WebSocket-Accept`（§14.1）。
2. 🐞 修复 `load-balance` 双重 `pick()` 导致的分流错位（§14.4）。
3. 🐞 修复 `/rules` 对 `SUB-RULE` payload 的截断（§14.2）。
4. 🐞 `/connections` 补齐明文 HTTP 转发路径（§14.3）。
5. `GET /providers/rules`、`GET /group/{name}/delay`、`GET /logs`(WS)、`GET /memory`。
6. `profile.store-selected`。
7. `rule` / `rulePayload` 字段与 mihomo 对齐（小写类型、payload 不含 target）。

---

## 13. 验证状态

### 13.1 已验证（本机实测，v1.3.1）

| 项 | 结论 |
|---|---|
| 18 个 REST 端点状态码与响应体 | ✅ 全部实测 |
| `PATCH /configs` 热切三种模式 + 写回 YAML | ✅ |
| `GET /configs` 小写 | ✅ `{"mode":"rule"}` |
| `/proxies/{group}/delay?member=` 语义 | ✅ 200 `{"delay":86}` |
| `/proxies/{node}/delay` 与 `/group/{name}/delay` | ✅ 均 404 |
| `/connections` 覆盖范围（三种客户端路径） | ✅ 明文 HTTP 不记录 |
| `SUB-RULE` 命中后的 `rule` 字段 | ✅ 显示子规则 |
| `chains` 折叠嵌套组 | ✅ `["LB","DIRECT"]` |
| `mode` 三种模式的实际路由 | ✅ rule/global/direct 各不同 |
| `load-balance` round-robin 错位 | ✅ 用 `XOOXOOXOO` 精确复现 |
| 严格 WS 客户端连 `/traffic` | 🐞 拒连 |
| `/rules` 的 SUB-RULE payload | 🐞 截断为 `"(NETWORK"` |
| 配置校验 `vpcore validate` | ✅ |

### 13.2 仍需验证

| 项 | 为什么没验 | 怎么验 |
|---|---|---|
| TUN 全流量是否真的生效 | 需要管理员权限，本会话无法提权 | 提权跑 `vpcore run`，开 `tun.enable`，看 `Get-NetRoute` 是否出现双 /1、`/connections` 是否记录非 fake-IP 目标 |
| Wintun 网卡是否拿到 `198.18.0.1` | 同上 | 开 TUN 后 `Get-NetIPAddress` |
| 出站绑卡是否真的生效 | 需 TUN 环境 | TUN 开启后抓连接源地址是否等于物理网卡 IP |
| `mrs` 格式 rule-provider | 缺少 mrs 样本文件 | 用 mihomo 导出一个 mrs 实测 |
| `url-test` / `fallback` 的实际切换 | 需要真实可测节点 | 用两个可控上游（一快一慢 / 一死一活） |
| `relay` 链式代理 | 需要真实可 relay 的两跳 | 起两个内核实例做两跳 |
| yacd / metacubexd 的 404 清单 | 需要面板 | 起内核 + 面板逐页点 |

---

## 14. 已确认缺陷（建议上报上游）

### 14.1 `/traffic` WebSocket 握手不合规

`api.rs:149-153`：

```rust
let resp = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\
            Connection: Upgrade\r\nSec-WebSocket-Accept: vpcore\r\n\r\n";
```

`Sec-WebSocket-Accept` 应为 `base64(sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))`，这里硬编码 `vpcore`。

**实测**：.NET `ClientWebSocket` 直接抛
`The 'Sec-WebSocket-Accept' header value 'vpcore' is invalid.`
Dart 的 `WebSocket.connect` 同样校验该头，预期也会失败。

### 14.2 `/rules` 截断 `SUB-RULE` payload

`api.rs:345-355` 用 `r.raw.split(',')` 取 `parts[1]` 作为 payload。对
`SUB-RULE,(NETWORK,tcp),grp` 而言 `parts[1]` 是 `"(NETWORK"`。

**实测**：`{"type":"SUB-RULE","payload":"(NETWORK","proxy":"grp"}` —— 括号内条件被截断，面板无法正确展示。

### 14.3 `/connections` 漏记明文 HTTP 转发

**实测（可稳定复现，v1.3.1）**：

```
curl -x http://127.0.0.1:17890 http://127.0.0.1:18080/slow      → /connections 恒为空
curl -x http://127.0.0.1:17890 -p http://127.0.0.1:18080/slow   → 立刻出现记录
curl --socks5 127.0.0.1:17890 http://127.0.0.1:18080/slow       → 立刻出现记录
```

**根因未定**：`vp-protocol/src/inbound/http_in.rs:176-199` 的 absolute-form 分支**确实**构造了带 `table: Some(ctx.conns.clone())` 的 `RelayHook` 并调用 `relay`，所以"没挂 hook"的猜测不成立，问题在更上游（请求是否真的走到该分支、或注册后被立即移除）。需要维护者定位。

### 14.4 `load-balance` round-robin 因双重 `pick()` 错位

`vp-router/src/group.rs:109-153`：`pick_index` 对 `RoundRobin` 用
`rr_counter.fetch_add(1) % n`——**每次调用都推进计数器**。而一次连接里 `pick()` 会被调用多次（至少一次用于日志展示、一次用于实际拨号）。

**后果**：

- `n = 2`：两次 `pick` 让索引永远落在同一奇偶 → **每条连接都选同一个成员**，负载均衡失效。
- `n = 3`：每次连接推进 2 格 → 分流错位。

**实测复现**（G1=DIRECT、G2=REJECT、G3=DIRECT，LB=[G1,G2,G3] round-robin，连续 9 次请求）：

```
实测序列: XOOXOOXOO
理论序列（若每次连接 pick 两次、3 成员）: XOOXOOXOO   ← 完全吻合
```

日志同时暴露了两次选择：

```
INFO  match DST-PORT,18080,LB using DIRECT[LB]              ← pick #1 选中 G1(DIRECT)
WARN  出站 LB 失败: unsupported: REJECT: 127.0.0.1:18080    ← pick #2 选中 G2(REJECT)
```

**修复方向**：把选成员的结果在单次连接内缓存（例如由 `Resolution` 携带索引），或把 `pick` 拆成「无副作用的查看」与「推进计数器的分配」两个方法。
