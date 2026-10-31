use std::io::{self, BufRead, Read, Write};

use flvp_host::{Host, MAX_REQUEST_BYTES, init_logging};

/// 计划任务启动的协助进程没有调用方的环境变量，必须从命令行拿到数据目录，
/// 否则 `FLVP_APP_SUPPORT_DIR` 为空，网络锁与 TUN 事务日志全部落到空路径。
fn apply_support_dir() -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(value) = arg.strip_prefix("--app-support-dir=") {
            // SAFETY: 单线程启动阶段设置，早于任何工作线程。
            unsafe { std::env::set_var("FLVP_APP_SUPPORT_DIR", value) };
            return Some(value.to_owned());
        }
        if arg == "--app-support-dir" {
            let value = args.next()?;
            unsafe { std::env::set_var("FLVP_APP_SUPPORT_DIR", &value) };
            return Some(value);
        }
    }
    None
}

fn main() -> io::Result<()> {
    init_logging();
    apply_support_dir();
    let mut host = Host::default();
    let mode = std::env::args().nth(1);
    if mode.as_deref() == Some("--elevated-serve") {
        return flvp_host::elevation::serve(&mut host);
    }
    if mode.as_deref() == Some("--recover-system-proxy") {
        let response = host.request(r#"{"requestId":"recovery","operation":"capabilities"}"#);
        if !response["result"]["systemProxyRecoveryError"].is_null() {
            return Err(io::Error::other(
                "System proxy recovery failed or settings changed externally",
            ));
        }
        return Ok(());
    }
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let stdout = io::stdout();
    let mut output = stdout.lock();
    loop {
        let mut bytes = Vec::new();
        let read = input
            .by_ref()
            .take((MAX_REQUEST_BYTES + 1) as u64)
            .read_until(b'\n', &mut bytes)?;
        if read == 0 {
            break;
        }
        if bytes.len() > MAX_REQUEST_BYTES || !bytes.ends_with(b"\n") {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid protocol frame",
            ));
        }
        let text = std::str::from_utf8(&bytes)
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "Invalid UTF-8"))?;
        let response = host.request(text);
        let quit = serde_json::from_str::<serde_json::Value>(text)
            .ok()
            .is_some_and(|r| r["operation"] == "quit")
            && response["ok"] == true;
        serde_json::to_writer(&mut output, &response)?;
        output.write_all(b"\n")?;
        output.flush()?;
        if quit {
            break;
        }
    }
    // Drop shuts down only this process's core; it never invokes a route cleaner.
    Ok(())
}
