//! Durable, compare-before-restore transaction for the current user's LAN
//! WinINet settings. No WinHTTP, RAS connection, routes or DNS changes.
#![cfg_attr(not(target_os = "windows"), allow(dead_code))]
use serde::{Deserialize, Serialize};
use std::{fs, io::Write, path::Path};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Settings {
    flags: u32,
    proxy: String,
    bypass: String,
    pac: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Journal {
    version: u32,
    transaction: String,
    owner_sid: String,
    before: Settings,
    after: Settings,
}

trait Backend {
    fn owner(&self) -> Result<String, String>;
    fn read(&self) -> Result<Settings, String>;
    fn write(&self, settings: &Settings) -> Result<(), String>;
}

fn journal(root: &Path) -> std::path::PathBuf {
    root.join("state/system-proxy.json")
}
fn load(root: &Path) -> Result<Option<Journal>, String> {
    let bytes = match fs::read(journal(root)) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("无法读取系统代理恢复日志".into()),
    };
    let value: Journal =
        serde_json::from_slice(&bytes).map_err(|_| "系统代理日志损坏，未修改系统设置")?;
    if value.version != 2 || value.transaction.is_empty() {
        return Err("系统代理日志版本不兼容，未修改系统设置".into());
    }
    Ok(Some(value))
}

fn enable_with(root: &Path, port: u16, backend: &impl Backend) -> Result<(), String> {
    if load(root)?.is_some() {
        return Err("系统代理尚有恢复事务，请先关闭或处理恢复冲突".into());
    }
    let before = backend.read()?;
    let after = Settings {
        flags: 3, // PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY; disables PAC and WPAD.
        proxy: format!("127.0.0.1:{port}"),
        bypass: "<local>;localhost;127.*;[::1]".into(),
        pac: String::new(),
    };
    let transaction = Journal {
        version: 2,
        owner_sid: backend.owner()?,
        transaction: format!("{}-{:?}", std::process::id(), std::time::SystemTime::now()),
        before,
        after: after.clone(),
    };
    fs::create_dir_all(root.join("state")).map_err(|_| "无法创建系统代理日志目录")?;
    let path = journal(root);
    let temporary = path.with_extension("tmp");
    let bytes = serde_json::to_vec(&transaction).map_err(|_| "无法序列化恢复日志")?;
    let mut file = fs::File::create(&temporary).map_err(|_| "无法创建恢复日志")?;
    file.write_all(&bytes)
        .and_then(|_| file.sync_all())
        .map_err(|_| "无法持久化恢复日志，未修改系统设置")?;
    drop(file);
    fs::rename(temporary, path).map_err(|_| "无法发布恢复日志，未修改系统设置")?;
    let result = backend.write(&after).and_then(|_| {
        if backend.read()? == after {
            Ok(())
        } else {
            Err("系统代理设置读回不一致".into())
        }
    });
    if let Err(error) = result {
        return match restore_with(root, backend) {
            Ok(_) => Err(format!("{error}；已恢复原设置")),
            Err(recovery) => Err(format!("{error}；{recovery}")),
        };
    }
    Ok(())
}

fn restorable(current: &Settings, value: &Journal) -> bool {
    // Also accepts an interrupted partial write/restoration, but never a value
    // outside the exact old/new pair for any affected field.
    (current.flags == value.before.flags || current.flags == value.after.flags)
        && (current.proxy == value.before.proxy || current.proxy == value.after.proxy)
        && (current.bypass == value.before.bypass || current.bypass == value.after.bypass)
        && (current.pac == value.before.pac || current.pac == value.after.pac)
}

fn restore_with(root: &Path, backend: &impl Backend) -> Result<bool, String> {
    let Some(value) = load(root)? else {
        return Ok(false);
    };
    if value.owner_sid != backend.owner()? {
        return Err("恢复日志不属于当前 Windows 用户，未修改系统设置".into());
    }
    let current = backend.read()?;
    if !restorable(&current, &value) {
        return Err("系统代理已被外部修改，未覆盖新设置；恢复日志已保留".into());
    }
    // Refresh even when values already match: the earlier process may have
    // failed between setting values and notifying WinINet.
    backend.write(&value.before)?;
    if backend.read()? != value.before {
        return Err("系统代理恢复读回不一致，保留恢复日志".into());
    }
    fs::remove_file(journal(root)).map_err(|_| "系统代理已恢复，但恢复日志清理失败")?;
    Ok(true)
}

#[cfg(target_os = "windows")]
mod platform {
    use super::*;
    use std::{ffi::c_void, mem::size_of, ptr::null_mut};
    use windows_sys::Win32::{
        Foundation::{CloseHandle, GlobalFree, LocalFree},
        Networking::WinInet::*,
        Security::{
            Authorization::ConvertSidToStringSidW, GetTokenInformation, TOKEN_QUERY, TOKEN_USER,
            TokenUser,
        },
        System::Threading::{GetCurrentProcess, OpenProcessToken},
    };

    pub struct WinInet;
    fn options(flags_option: u32) -> [INTERNET_PER_CONN_OPTIONW; 4] {
        [
            flags_option,
            INTERNET_PER_CONN_PROXY_SERVER,
            INTERNET_PER_CONN_PROXY_BYPASS,
            INTERNET_PER_CONN_AUTOCONFIG_URL,
        ]
        .map(|dw_option| INTERNET_PER_CONN_OPTIONW {
            dwOption: dw_option,
            Value: INTERNET_PER_CONN_OPTIONW_0 { dwValue: 0 },
        })
    }
    fn list(opts: &mut [INTERNET_PER_CONN_OPTIONW; 4]) -> INTERNET_PER_CONN_OPTION_LISTW {
        INTERNET_PER_CONN_OPTION_LISTW {
            dwSize: size_of::<INTERNET_PER_CONN_OPTION_LISTW>() as u32,
            pszConnection: null_mut(),
            dwOptionCount: opts.len() as u32,
            dwOptionError: 0,
            pOptions: opts.as_mut_ptr(),
        }
    }
    unsafe fn take_string(ptr: *mut u16) -> String {
        if ptr.is_null() {
            return String::new();
        }
        let mut len = 0;
        unsafe {
            while *ptr.add(len) != 0 {
                len += 1;
            }
            let result = String::from_utf16_lossy(std::slice::from_raw_parts(ptr, len));
            GlobalFree(ptr.cast());
            result
        }
    }
    impl Backend for WinInet {
        fn owner(&self) -> Result<String, String> {
            unsafe {
                let mut token = null_mut();
                if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
                    return Err("无法读取当前用户身份".into());
                }
                let mut length = 0;
                GetTokenInformation(token, TokenUser, null_mut(), 0, &mut length);
                let mut buffer = vec![0usize; (length as usize).div_ceil(size_of::<usize>())];
                let ok = GetTokenInformation(
                    token,
                    TokenUser,
                    buffer.as_mut_ptr().cast(),
                    length,
                    &mut length,
                );
                CloseHandle(token);
                if ok == 0 {
                    return Err("无法读取当前用户 SID".into());
                }
                let user = &*buffer.as_ptr().cast::<TOKEN_USER>();
                let mut text = null_mut();
                if ConvertSidToStringSidW(user.User.Sid, &mut text) == 0 {
                    return Err("无法解析当前用户 SID".into());
                }
                let mut len = 0;
                while *text.add(len) != 0 {
                    len += 1;
                }
                let sid = String::from_utf16_lossy(std::slice::from_raw_parts(text, len));
                LocalFree(text.cast());
                Ok(sid)
            }
        }
        fn read(&self) -> Result<Settings, String> {
            let mut opts = options(INTERNET_PER_CONN_FLAGS_UI);
            let mut list = list(&mut opts);
            let mut size = list.dwSize;
            let ok = unsafe {
                InternetQueryOptionW(
                    std::ptr::null(),
                    INTERNET_OPTION_PER_CONNECTION_OPTION,
                    (&mut list as *mut INTERNET_PER_CONN_OPTION_LISTW).cast(),
                    &mut size,
                )
            };
            // WinINet returns allocated strings; release every returned buffer.
            let proxy = unsafe { take_string(opts[1].Value.pszValue) };
            let bypass = unsafe { take_string(opts[2].Value.pszValue) };
            let pac = unsafe { take_string(opts[3].Value.pszValue) };
            if ok == 0 {
                return Err("WinINet 读取 LAN 连接设置失败".into());
            }
            Ok(Settings {
                flags: unsafe { opts[0].Value.dwValue },
                proxy,
                bypass,
                pac,
            })
        }
        fn write(&self, value: &Settings) -> Result<(), String> {
            let wide = |s: &str| s.encode_utf16().chain(Some(0)).collect::<Vec<_>>();
            let mut proxy = wide(&value.proxy);
            let mut bypass = wide(&value.bypass);
            let mut pac = wide(&value.pac);
            let mut opts = options(INTERNET_PER_CONN_FLAGS);
            opts[0].Value.dwValue = value.flags;
            opts[1].Value.pszValue = proxy.as_mut_ptr();
            opts[2].Value.pszValue = bypass.as_mut_ptr();
            opts[3].Value.pszValue = pac.as_mut_ptr();
            let mut list = list(&mut opts);
            let ok = unsafe {
                InternetSetOptionW(
                    std::ptr::null(),
                    INTERNET_OPTION_PER_CONNECTION_OPTION,
                    (&mut list as *mut INTERNET_PER_CONN_OPTION_LISTW).cast::<c_void>(),
                    list.dwSize,
                )
            };
            if ok == 0 {
                return Err("WinINet 设置 LAN 连接代理失败".into());
            }
            let changed = unsafe {
                InternetSetOptionW(
                    std::ptr::null(),
                    INTERNET_OPTION_SETTINGS_CHANGED,
                    std::ptr::null(),
                    0,
                )
            };
            let refreshed = unsafe {
                InternetSetOptionW(
                    std::ptr::null(),
                    INTERNET_OPTION_REFRESH,
                    std::ptr::null(),
                    0,
                )
            };
            if changed == 0 || refreshed == 0 {
                return Err("WinINet 刷新代理设置失败".into());
            }
            Ok(())
        }
    }
    pub fn enable(root: &Path, port: u16) -> Result<(), String> {
        enable_with(root, port, &WinInet)
    }
    pub fn restore(root: &Path) -> Result<bool, String> {
        restore_with(root, &WinInet)
    }
    pub fn is_active(root: &Path) -> bool {
        load(root).ok().flatten().is_some_and(|j| {
            WinInet.owner().is_ok_and(|s| s == j.owner_sid)
                && WinInet.read().is_ok_and(|s| s == j.after)
        })
    }
}
#[cfg(not(target_os = "windows"))]
mod platform {
    use std::path::Path;
    pub fn enable(_: &Path, _: u16) -> Result<(), String> {
        Err("系统代理仅支持 Windows".into())
    }
    pub fn restore(_: &Path) -> Result<bool, String> {
        Ok(false)
    }
    pub fn is_active(_: &Path) -> bool {
        false
    }
}
pub use platform::{enable, is_active, restore};

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};
    struct Fake {
        value: RefCell<Settings>,
        fail_once: Cell<bool>,
    }
    impl Backend for Fake {
        fn owner(&self) -> Result<String, String> {
            Ok("test-user".into())
        }
        fn read(&self) -> Result<Settings, String> {
            Ok(self.value.borrow().clone())
        }
        fn write(&self, value: &Settings) -> Result<(), String> {
            *self.value.borrow_mut() = value.clone();
            if self.fail_once.replace(false) {
                Err("notification failed".into())
            } else {
                Ok(())
            }
        }
    }
    fn setup() -> (std::path::PathBuf, Fake) {
        static SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!(
            "flvp-proxy-test-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ));
        let backend = Fake {
            value: RefCell::new(Settings {
                flags: 13,
                proxy: "http=old:8123".into(),
                bypass: "*.example".into(),
                pac: "https://example.invalid/pac".into(),
            }),
            fail_once: Cell::new(false),
        };
        (root, backend)
    }
    #[test]
    fn restores_pac_wpad_and_manual_values_after_restart() {
        let (root, backend) = setup();
        let old = backend.read().unwrap();
        enable_with(&root, 17890, &backend).unwrap();
        assert_eq!(backend.read().unwrap().flags, 3);
        assert!(restore_with(&root, &backend).unwrap());
        assert_eq!(backend.read().unwrap(), old);
        assert!(!restore_with(&root, &backend).unwrap());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn foreign_change_preserves_all_settings_and_journal() {
        let (root, backend) = setup();
        enable_with(&root, 17890, &backend).unwrap();
        backend.value.borrow_mut().proxy = "other:9999".into();
        let foreign = backend.read().unwrap();
        assert!(restore_with(&root, &backend).is_err());
        assert_eq!(backend.read().unwrap(), foreign);
        assert!(journal(&root).exists());
        assert!(enable_with(&root, 17891, &backend).is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn notification_failure_rolls_back_and_partial_restore_is_retryable() {
        let (root, backend) = setup();
        let old = backend.read().unwrap();
        backend.fail_once.set(true);
        assert!(enable_with(&root, 17890, &backend).is_err());
        assert_eq!(backend.read().unwrap(), old);
        enable_with(&root, 17890, &backend).unwrap();
        backend.value.borrow_mut().flags = old.flags;
        assert!(restore_with(&root, &backend).unwrap());
        assert_eq!(backend.read().unwrap(), old);
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn corrupt_journal_does_not_write_settings() {
        let (root, backend) = setup();
        fs::create_dir_all(root.join("state")).unwrap();
        fs::write(journal(&root), b"{}").unwrap();
        let old = backend.read().unwrap();
        assert!(restore_with(&root, &backend).is_err());
        assert_eq!(backend.read().unwrap(), old);
        fs::remove_dir_all(root).unwrap();
    }
}
