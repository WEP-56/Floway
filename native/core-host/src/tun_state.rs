//! TUN 路由事务日志：进入 TUN 前记录接管信息，正常退出时清理；
//! 若上次进程被强杀导致日志残留，下次启动先清掉孤儿路由再回报。
//!
//! DNS 不做系统级改写（内核只在 TUN 内劫持报文），因此事务日志只覆盖路由。

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Record {
    pub address: String,
    pub netmask: String,
    pub pid: u32,
    pub started_at: u64,
}

fn state_path(root: &Path) -> PathBuf {
    root.join("state/tun.json")
}

pub fn record(root: &Path, address: &str, netmask: &str) -> std::io::Result<()> {
    std::fs::create_dir_all(root.join("state"))?;
    let record = Record {
        address: address.to_owned(),
        netmask: netmask.to_owned(),
        pid: std::process::id(),
        started_at: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
    };
    std::fs::write(state_path(root), serde_json::to_vec(&record)?)
}

pub fn clear(root: &Path) {
    let _ = std::fs::remove_file(state_path(root));
}

pub fn pending(root: &Path) -> Option<Record> {
    let mut text = std::fs::read(state_path(root)).ok()?;
    // 兼容带 BOM 的写入方（曾在 provider 索引上踩过）。
    if text.starts_with(&[0xEF, 0xBB, 0xBF]) {
        text.drain(..3);
    }
    serde_json::from_slice(&text).ok()
}

/// 计算 IPv4 网络地址。
pub fn network_of(address: &str, netmask: &str) -> Option<String> {
    let addr: u32 = ipv4(address)?;
    let mask: u32 = ipv4(netmask)?;
    let net = addr & mask;
    Some(format!(
        "{}.{}.{}.{}",
        net >> 24,
        (net >> 16) & 0xff,
        (net >> 8) & 0xff,
        net & 0xff
    ))
}

fn ipv4(text: &str) -> Option<u32> {
    let parts: Vec<&str> = text.split('.').collect();
    if parts.len() != 4 {
        return None;
    }
    let mut value = 0u32;
    for part in parts {
        let byte: u32 = part.parse().ok()?;
        if byte > 255 {
            return None;
        }
        value = (value << 8) | byte;
    }
    Some(value)
}

/// 只删本进程本该持有的路由，不碰系统其它条目。
pub fn cleanup_routes(address: &str, netmask: &str) {
    #[cfg(windows)]
    {
        if let Some(net) = network_of(address, netmask) {
            let _ = Command::new("route")
                .args(["delete", &net, "mask", netmask, address])
                .output();
        }
        for (net, mask) in [("0.0.0.0", "128.0.0.0"), ("128.0.0.0", "128.0.0.0")] {
            let _ = Command::new("route")
                .args(["delete", net, "mask", mask])
                .output();
        }
    }
    #[cfg(not(windows))]
    {
        let _ = (address, netmask);
    }
}

/// 启动时调用：上次异常退出留下的 TUN 记录要清掉并回报。
pub fn recover(root: &Path) -> Option<String> {
    let record = pending(root)?;
    cleanup_routes(&record.address, &record.netmask);
    clear(root);
    Some(format!(
        "已清理上次异常退出（PID {}）残留的 TUN 路由",
        record.pid
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "flvp-tun-state-{}-{:?}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn network_address_uses_mask() {
        assert_eq!(network_of("198.18.0.1", "255.255.0.0").as_deref(), Some("198.18.0.0"));
        assert_eq!(network_of("10.1.2.3", "255.255.255.0").as_deref(), Some("10.1.2.0"));
        assert_eq!(network_of("bad", "255.0.0.0"), None);
    }

    #[test]
    fn record_clear_and_recover_roundtrip() {
        let root = temp_root();
        assert!(pending(&root).is_none());
        record(&root, "198.18.0.1", "255.255.0.0").unwrap();
        let stored = pending(&root).expect("record should exist");
        assert_eq!(stored.address, "198.18.0.1");
        assert_eq!(stored.pid, std::process::id());
        let message = recover(&root).expect("stale record must be reported");
        assert!(message.contains("残留"), "{message}");
        assert!(pending(&root).is_none());
        assert!(recover(&root).is_none());
        record(&root, "198.18.0.1", "255.255.0.0").unwrap();
        clear(&root);
        assert!(pending(&root).is_none());
        let _ = std::fs::remove_dir_all(root);
    }
}
