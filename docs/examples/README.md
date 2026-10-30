# 配置样例与边界用例

这里的文件分为正向 schema 样例与“静态校验不足”的证据用例。它们不包含真实节点凭据，不触碰系统代理或系统路由。

| 文件 | 用途 | 上游 validate 预期 |
| --- | --- | --- |
| `minimal.yaml` | 普通 mixed + 显式最终规则，TUN 关闭 | 成功 |
| `rules.yaml` | 域名、CIDR、逻辑、子规则、最终 MATCH | 成功 |
| `android-template.yaml` | Android 生成结构；FD 不写盘、auto-route 显式关闭 | 成功；不代表可运行 VPN |
| `providers.yaml` + `domains.yaml` | 本地 domain provider，便于装配调研 | 成功；静态 validate 不读取资源 |
| `invalid-reference.yaml` | 组引用不存在 | 失败 |
| `limitations/unknown-field.yaml` | `sniffer` 未知字段可被忽略 | 成功，但 FLVPcore 严格导入应拒绝未验证功能 |
| `limitations/unknown-rule.yaml` | 未知规则没有被静态 validate 检出 | 成功，但 FLVPcore 必须拒绝 |
| `limitations/overflow-port.yaml` | 字符串端口 65536 在宽松转换中截断 | 成功，但 FLVPcore 必须拒绝 |

`providers.yaml` 使用相对路径仅用于阅读和本地复现；生产编译器必须转换成受控绝对路径。`android-template.yaml` 仅做 schema 验证，禁止直接交给未修补 vp_start 当作完成 VPN 接入。

根目录执行 `python tools/verify_research.py` 可运行上游相关单测、构建 CLI、逐个验证上述预期并检查本地 Markdown 链接；`--docs-only` 仅检查文档。脚本不会启动 CLI run 或清理路由。
