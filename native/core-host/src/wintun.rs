//! Wintun 驱动定位。
//!
//! 内核的 TUN 数据面在 Windows 上依赖 `wintun.dll`。内核自己会做一次探测，
//! 但探测失败时只打一行 warn 就继续启动，调用方拿不到原因，界面只能看到
//! 一句笼统的超时。这里在内核启动前用同样的搜索顺序做一次预检，
//! 把「找不到驱动」变成带期望路径的明确错误。
//!
//! 搜索顺序与 vp-tun 的 `wintun_installer` 保持一致：环境变量 → 可执行文件
//! 同级 → 架构子目录 → 工作目录 → 用户数据目录 → 临时目录 → System32。

use std::path::{Path, PathBuf};

fn arch_relative() -> &'static str {
    #[cfg(target_arch = "x86_64")]
    {
        "wintun/bin/amd64/wintun.dll"
    }
    #[cfg(target_arch = "aarch64")]
    {
        "wintun/bin/arm64/wintun.dll"
    }
    #[cfg(target_arch = "x86")]
    {
        "wintun/bin/x86/wintun.dll"
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64", target_arch = "x86")))]
    {
        "wintun.dll"
    }
}

/// 返回第一个存在的候选路径。
pub fn locate() -> Option<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(explicit) = std::env::var_os("WINTUN_DLL_PATH") {
        candidates.push(PathBuf::from(explicit));
    }
    if let Ok(exe) = std::env::current_exe()
        && let Some(dir) = exe.parent()
    {
        candidates.push(dir.join("wintun.dll"));
        candidates.push(dir.join(arch_relative()));
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.join("wintun.dll"));
        candidates.push(cwd.join(arch_relative()));
    }
    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        candidates.push(Path::new(&local).join("vpcore").join("wintun.dll"));
    }
    candidates.push(std::env::temp_dir().join("vpcore").join("wintun.dll"));
    if let Some(root) = std::env::var_os("SystemRoot") {
        candidates.push(Path::new(&root).join("System32").join("wintun.dll"));
    }
    candidates.into_iter().find(|path| path.is_file())
}

/// 预检：TUN 开启时若找不到驱动，直接给出可执行的修复指引。
pub fn require() -> Result<PathBuf, String> {
    locate().ok_or_else(|| {
        let expected = std::env::current_exe()
            .ok()
            .and_then(|exe| exe.parent().map(|dir| dir.join("wintun.dll")))
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| "flvp-core-host.exe 同级目录".to_owned());
        format!(
            "未找到 Wintun 驱动 wintun.dll：TUN 需要它创建虚拟网卡。\
             请把 wintun.dll 放到 {expected}（或设置环境变量 WINTUN_DLL_PATH 指向该文件）。"
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 两个用例都改同一个进程级环境变量，必须串行，否则会互相看到对方的路径。
    fn env_guard() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
        LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[test]
    fn explicit_env_path_wins() {
        let _guard = env_guard();
        let dir = std::env::temp_dir().join(format!("flvp-wintun-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let dll = dir.join("custom.dll");
        std::fs::write(&dll, b"stub").unwrap();
        // SAFETY: 已用 env_guard 串行化，且只改动本测试自己的变量。
        unsafe { std::env::set_var("WINTUN_DLL_PATH", &dll) };
        let found = locate();
        unsafe { std::env::remove_var("WINTUN_DLL_PATH") };
        assert_eq!(found.as_deref(), Some(dll.as_path()));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn missing_driver_reports_expected_path() {
        let _guard = env_guard();
        let dir = std::env::temp_dir().join(format!("flvp-wintun-miss-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let absent = dir.join("absent.dll");
        unsafe { std::env::set_var("WINTUN_DLL_PATH", &absent) };
        // 即使候选不存在，后续候选也可能命中系统目录，因此这里只校验错误文案。
        let error = require().err();
        unsafe { std::env::remove_var("WINTUN_DLL_PATH") };
        if let Some(message) = error {
            assert!(message.contains("wintun.dll"), "{message}");
            assert!(message.contains("WINTUN_DLL_PATH"), "{message}");
        }
        let _ = std::fs::remove_dir_all(dir);
    }
}
