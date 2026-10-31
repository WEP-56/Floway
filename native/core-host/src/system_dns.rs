//! 系统 DNS 接管：TUN 模式下把物理网卡的 DNS 指向内核的 fake-IP 解析器。
//!
//! 为什么必须接管：vp_core 的 `auto-route` 只把 fake-IP 网段（198.18.0.0/16）
//! 路由进 TUN，不做全流量接管。域名必须先解析成 fake-IP 才会进入隧道，所以
//! DNS 必须由内核回答。内核在 `0.0.0.0:53` 起了带 fake-IP 池的解析器，客户端
//! 负责把系统 DNS 指过去——参考实现 vpn-parser 正是把网卡上的
//! 127.0.0.1 / 198.18.0.1 当作内核 TUN 留下的痕迹来清理。
//!
//! 不接管 DNS 的表现就是：TUN 开关显示已开启，但所有域名仍解析成真实 IP，
//! 流量走物理网卡，出口 IP 依旧是本机 IP。
//!
//! 事务语义与 `system_proxy` 一致：先落盘「原值」，再改，改后读回校验；
//! 恢复时逐项比对，绝不用日志里的旧值覆盖已被外部修改的设置。

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};

/// 指向内核 fake-IP 解析器。用回环地址而不是 198.18.0.1：
/// 回环不依赖路由，只要内核在 0.0.0.0:53 上监听就能答。
const HIJACK_DNS: &str = "127.0.0.1";

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdapterDns {
    pub alias: String,
    pub servers: Vec<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Journal {
    version: u32,
    transaction: String,
    before: Vec<AdapterDns>,
}

fn journal_path(root: &Path) -> PathBuf {
    root.join("state/system-dns.json")
}

fn load(root: &Path) -> Result<Option<Journal>, String> {
    let bytes = match std::fs::read(journal_path(root)) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("无法读取 DNS 接管恢复日志".into()),
    };
    let value: Journal =
        serde_json::from_slice(&bytes).map_err(|_| "DNS 接管日志损坏，未修改系统设置")?;
    if value.version != 1 {
        return Err("DNS 接管日志版本不兼容，未修改系统设置".into());
    }
    Ok(Some(value))
}

fn run_script(script: &str) -> Result<String, String> {
    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map_err(|e| format!("无法调用 PowerShell: {e}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let detail = stderr.trim();
        return Err(if detail.is_empty() {
            "PowerShell 执行失败".to_owned()
        } else {
            format!("PowerShell 执行失败: {detail}")
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

/// 列出需要接管的网卡：已启用、有默认网关（物理网卡）、且不是我们的 TUN。
/// 返回 `alias|server1,server2` 形式的行。
fn dump_script() -> String {
    r#"
$ErrorActionPreference = 'Stop'
Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
  Where-Object { $_.Status -eq 'Up' } |
  ForEach-Object {
    $alias = $_.Name
    $v4 = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($null -eq $v4) { return }
    $servers = @($v4.ServerAddresses | Where-Object { $_ })
    Write-Output ($alias + '|' + ($servers -join ','))
  }
"#
    .to_owned()
}

/// 解析 `dump_script` 的输出。空服务器列表也要保留：原先是 DHCP 自动获取，
/// 恢复时必须能表达「清空」而不是「恢复成空数组」。
pub fn parse_dump(text: &str) -> Vec<AdapterDns> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() {
                return None;
            }
            let (alias, servers) = line.split_once('|')?;
            let alias = alias.trim();
            if alias.is_empty() {
                return None;
            }
            Some(AdapterDns {
                alias: alias.to_owned(),
                servers: servers
                    .split(',')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned)
                    .collect(),
            })
        })
        .collect()
}

/// 已经指向 fake-IP 解析器的网卡不需要重复接管。
pub fn needs_hijack(adapters: &[AdapterDns]) -> Vec<AdapterDns> {
    adapters
        .iter()
        .filter(|adapter| {
            !(adapter.servers.len() == 1 && adapter.servers[0] == HIJACK_DNS)
        })
        .cloned()
        .collect()
}

fn set_script(adapters: &[AdapterDns]) -> String {
    let mut script = String::from(
        "$ErrorActionPreference = 'Stop'\n$failed = @()\n",
    );
    for adapter in adapters {
        let alias = adapter.alias.replace('\'', "''");
        script.push_str(&format!(
            "try {{ Set-DnsClientServerAddress -InterfaceAlias '{alias}' \
             -ServerAddresses '{HIJACK_DNS}' -ErrorAction Stop }} \
             catch {{ $failed += '{alias}' }}\n"
        ));
    }
    script.push_str(
        "Clear-DnsClientCache -ErrorAction SilentlyContinue\n\
         if ($failed.Count -gt 0) { Write-Error ('无法设置 DNS: ' + ($failed -join ', ')); exit 1 }\n\
         'OK'\n",
    );
    script
}

fn restore_script(adapters: &[AdapterDns]) -> String {
    let mut script = String::from(
        "$ErrorActionPreference = 'Stop'\n$failed = @()\n",
    );
    for adapter in adapters {
        let alias = adapter.alias.replace('\'', "''");
        if adapter.servers.is_empty() {
            // 原本就是 DHCP 自动获取：重置回自动，而不是留一组空值。
            script.push_str(&format!(
                "try {{ Set-DnsClientServerAddress -InterfaceAlias '{alias}' \
                 -ResetServerAddresses -ErrorAction Stop }} \
                 catch {{ $failed += '{alias}' }}\n"
            ));
        } else {
            let servers = adapter
                .servers
                .iter()
                .map(|s| format!("'{s}'"))
                .collect::<Vec<_>>()
                .join(",");
            script.push_str(&format!(
                "try {{ Set-DnsClientServerAddress -InterfaceAlias '{alias}' \
                 -ServerAddresses @({servers}) -ErrorAction Stop }} \
                 catch {{ $failed += '{alias}' }}\n"
            ));
        }
    }
    script.push_str(
        "Clear-DnsClientCache -ErrorAction SilentlyContinue\n\
         if ($failed.Count -gt 0) { Write-Error ('无法恢复 DNS: ' + ($failed -join ', ')); exit 1 }\n\
         'OK'\n",
    );
    script
}

/// 接管系统 DNS。返回实际被修改的网卡。
pub fn enable(root: &Path) -> Result<Vec<AdapterDns>, String> {
    if let Some(existing) = load(root)? {
        // 已有接管事务：热重载或重复 start 时保持现状，不要报冲突，
        // 否则「TUN 开着改配置」会整条失败。
        let current = parse_dump(&run_script(&dump_script())?);
        let still_hijacked = existing.before.iter().any(|before| {
            current.iter().any(|now| {
                now.alias == before.alias
                    && now.servers.len() == 1
                    && now.servers[0] == HIJACK_DNS
            })
        });
        if still_hijacked {
            return Ok(Vec::new());
        }
        return Err("DNS 接管尚有恢复事务，请先关闭 TUN 或处理恢复冲突".into());
    }
    let current = parse_dump(&run_script(&dump_script())?);
    if current.is_empty() {
        return Err("未找到可接管的物理网卡，无法接管 DNS".into());
    }
    let targets = needs_hijack(&current);
    if targets.is_empty() {
        return Ok(Vec::new());
    }
    std::fs::create_dir_all(root.join("state")).map_err(|_| "无法创建 DNS 接管日志目录")?;
    let journal = Journal {
        version: 1,
        transaction: format!("{}-{:?}", std::process::id(), std::time::SystemTime::now()),
        before: targets.clone(),
    };
    let bytes = serde_json::to_vec(&journal).map_err(|_| "无法序列化 DNS 接管日志")?;
    let path = journal_path(root);
    let temporary = path.with_extension("tmp");
    std::fs::write(&temporary, &bytes).map_err(|_| "无法写入 DNS 接管日志")?;
    std::fs::rename(&temporary, &path).map_err(|_| "无法发布 DNS 接管日志")?;

    if let Err(error) = run_script(&set_script(&targets)) {
        // 改失败就立刻回滚，不留半接管状态。
        let _ = restore(root);
        return Err(error);
    }
    Ok(targets)
}

/// 恢复被接管的 DNS。返回是否真的做了恢复。
pub fn restore(root: &Path) -> Result<bool, String> {
    let Some(journal) = load(root)? else {
        return Ok(false);
    };
    // 只恢复仍然指向我们的网卡；用户手工改过的保持不动。
    let current = parse_dump(&run_script(&dump_script())?);
    let still_ours: Vec<AdapterDns> = journal
        .before
        .iter()
        .filter(|before| {
            current
                .iter()
                .find(|now| now.alias == before.alias)
                .is_some_and(|now| {
                    now.servers.len() == 1 && now.servers[0] == HIJACK_DNS
                })
        })
        .cloned()
        .collect();
    if !still_ours.is_empty() {
        run_script(&restore_script(&still_ours))?;
    }
    std::fs::remove_file(journal_path(root)).map_err(|_| "无法删除 DNS 接管日志")?;
    Ok(true)
}

/// 是否有待恢复的接管事务（供启动自愈判断）。
pub fn has_journal(root: &Path) -> bool {
    journal_path(root).exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dump_parsing_keeps_empty_server_lists() {
        let parsed = parse_dump("以太网|192.168.1.1,8.8.8.8\nWLAN|\n\n  本地连接 5|127.0.0.1\n");
        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed[0].alias, "以太网");
        assert_eq!(parsed[0].servers, ["192.168.1.1", "8.8.8.8"]);
        assert_eq!(parsed[1].alias, "WLAN");
        assert!(parsed[1].servers.is_empty(), "DHCP 自动获取必须保留为空");
        assert_eq!(parsed[2].alias, "本地连接 5");
    }

    #[test]
    fn already_hijacked_adapters_are_skipped() {
        let adapters = vec![
            AdapterDns { alias: "WLAN".into(), servers: vec!["192.168.1.1".into()] },
            AdapterDns { alias: "已接管".into(), servers: vec![HIJACK_DNS.into()] },
            AdapterDns { alias: "双上游".into(), servers: vec![HIJACK_DNS.into(), "8.8.8.8".into()] },
        ];
        let targets = needs_hijack(&adapters);
        assert_eq!(targets.len(), 2, "只有已经完全是 127.0.0.1 的才跳过");
        assert_eq!(targets[0].alias, "WLAN");
        assert_eq!(targets[1].alias, "双上游");
    }

    #[test]
    fn restore_script_resets_dhcp_adapters_instead_of_clearing() {
        let script = restore_script(&[
            AdapterDns { alias: "WLAN".into(), servers: vec![] },
            AdapterDns { alias: "以太网".into(), servers: vec!["10.0.0.1".into()] },
        ]);
        assert!(script.contains("-ResetServerAddresses"), "{script}");
        assert!(script.contains("-ServerAddresses @('10.0.0.1')"), "{script}");
        assert!(script.contains("Clear-DnsClientCache"), "{script}");
    }

    #[test]
    fn single_quotes_in_alias_are_escaped() {
        let script = set_script(&[AdapterDns {
            alias: "Bob's LAN".into(),
            servers: vec![],
        }]);
        assert!(script.contains("'Bob''s LAN'"), "{script}");
    }
}
