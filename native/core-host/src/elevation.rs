//! 管理员协助进程：TUN 需要管理员权限，参考 FlClash 的常驻 Helper
//! （services/helper，Windows 服务 + 本地 HTTP 控制面）做的简化版本。
//!
//! 这里用「计划任务 + 本地回环 TCP」实现同样的用户体验：
//! 首次安装计划任务时弹一次 UAC，之后以 SYSTEM 身份常驻，应用静默连接。

use std::io::{self, BufRead, BufReader, Write};
use std::net::{IpAddr, TcpListener, TcpStream};
use std::path::PathBuf;

use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use crate::MAX_REQUEST_BYTES;

pub const HELPER_PORT: u16 = 38_765;
pub const HELPER_TASK_NAME: &str = "FLVPcoreHelper";
const HELPER_VERSION: &str = env!("CARGO_PKG_VERSION");

pub fn helper_dir() -> Option<PathBuf> {
    let base = std::env::var_os("PROGRAMDATA")?;
    Some(PathBuf::from(base).join("FLVPcore"))
}

fn token_path() -> Option<PathBuf> {
    helper_dir().map(|dir| dir.join("token"))
}

pub fn endpoint_path() -> Option<PathBuf> {
    helper_dir().map(|dir| dir.join("endpoint.json"))
}

#[cfg(target_os = "windows")]
pub fn is_elevated() -> bool {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::Security::{
        GetTokenInformation, TOKEN_ELEVATION, TOKEN_QUERY, TokenElevation,
    };
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    unsafe {
        let mut token = std::ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
            return false;
        }
        let mut elevation = TOKEN_ELEVATION { TokenIsElevated: 0 };
        let mut size = 0u32;
        let ok = GetTokenInformation(
            token,
            TokenElevation,
            (&raw mut elevation).cast(),
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut size,
        );
        CloseHandle(token);
        ok != 0 && elevation.TokenIsElevated != 0
    }
}

#[cfg(not(target_os = "windows"))]
pub fn is_elevated() -> bool {
    false
}

/// 读取（必要时生成）协助进程的共享令牌。
pub fn ensure_token() -> io::Result<String> {
    let path = token_path().ok_or_else(|| io::Error::other("PROGRAMDATA is unavailable"))?;
    if let Ok(existing) = std::fs::read_to_string(&path) {
        let trimmed = existing.trim();
        if trimmed.len() == 64 && trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
            return Ok(trimmed.to_owned());
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let seed = format!(
        "{}-{}-{:?}",
        std::process::id(),
        HELPER_VERSION,
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default()
    );
    let token = format!("{:x}", Sha256::digest(seed.as_bytes()));
    std::fs::write(&path, &token)?;
    Ok(token)
}

pub fn read_token() -> io::Result<String> {
    let path = token_path().ok_or_else(|| io::Error::other("PROGRAMDATA is unavailable"))?;
    Ok(std::fs::read_to_string(path)?.trim().to_owned())
}

fn write_endpoint() -> io::Result<()> {
    let path = endpoint_path().ok_or_else(|| io::Error::other("PROGRAMDATA is unavailable"))?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let body = json!({
        "port": HELPER_PORT,
        "pid": std::process::id(),
        "version": HELPER_VERSION,
        "elevated": is_elevated(),
    });
    std::fs::write(path, body.to_string())
}

fn respond(stream: &mut TcpStream, value: &Value) -> io::Result<()> {
    serde_json::to_writer(&mut *stream, value)?;
    stream.write_all(b"\n")?;
    stream.flush()
}

fn serve_connection(mut stream: TcpStream, host: &mut crate::Host, token: &str) -> io::Result<()> {
    let peer = stream.peer_addr()?;
    if !matches!(peer.ip(), IpAddr::V4(ip) if ip.is_loopback()) {
        return Ok(());
    }
    let reader = BufReader::new(stream.try_clone()?);
    let mut authed = false;
    for line in reader.lines() {
        let line = line?;
        if line.len() > MAX_REQUEST_BYTES {
            return Ok(());
        }
        let value: Value = serde_json::from_str(&line).unwrap_or(Value::Null);
        if !authed {
            let supplied = value["token"].as_str().unwrap_or_default();
            if value["operation"] == "hello" && supplied == token {
                authed = true;
                respond(
                    &mut stream,
                    &json!({"ok": true, "result": {"helper": true, "version": HELPER_VERSION,
                        "elevated": is_elevated()}}),
                )?;
            } else {
                respond(
                    &mut stream,
                    &json!({"ok": false, "error": {"code": "HELPER_UNAUTHORIZED",
                        "message": "协助进程令牌不匹配"}}),
                )?;
                return Ok(());
            }
            continue;
        }
        let quit = value["operation"] == "quit";
        let response = host.request(&line);
        let ok = response["ok"] == true;
        respond(&mut stream, &response)?;
        if quit && ok {
            break;
        }
    }
    Ok(())
}

/// 常驻服务入口：绑定回环端口，串行处理连接。
pub fn serve(host: &mut crate::Host) -> io::Result<()> {
    if !is_elevated() {
        return Err(io::Error::other(
            "协助进程需要管理员权限，请通过管理员终端安装计划任务",
        ));
    }
    let token = ensure_token()?;
    let listener = TcpListener::bind(("127.0.0.1", HELPER_PORT))?;
    write_endpoint()?;
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let _ = serve_connection(stream, host, &token);
            }
            Err(error) => {
                eprintln!("helper connection failed: {error}");
            }
        }
    }
    Ok(())
}
