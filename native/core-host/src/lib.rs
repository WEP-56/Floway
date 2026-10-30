//! First native host milestone: explicitly scoped, loopback-only ordinary proxy.
//! No upstream CLI, route cleaner, external controller, TUN or provider downloader.

mod config;

use std::ffi::{CStr, CString, c_char};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::Path;
use std::sync::{Arc, Mutex, Once, OnceLock};
use std::time::Duration;

use serde::Deserialize;
use serde_json::{Value, json};
use vp_app::App;
use vp_config::Format;

use config::PreparedConfig;

pub const CORE_COMMIT: &str = "fa3e7430371930c440ffb1bdccc6869c63554a34";
pub const MAX_REQUEST_BYTES: usize = 1024 * 1024;
pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Request {
    request_id: String,
    operation: String,
    #[serde(default)]
    expected_generation: Option<u64>,
    #[serde(default)]
    expected_applied_revision: Option<u64>,
    #[serde(default)]
    arguments: Value,
}

struct Running {
    app: Arc<App>,
    runtime: tokio::runtime::Runtime,
    config: PreparedConfig,
}

impl Running {
    fn start(config: PreparedConfig) -> Result<Self, String> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("flvp-core")
            .build()
            .map_err(|_| "Cannot create core runtime".to_owned())?;
        let result = runtime.block_on(async {
            tokio::time::timeout(
                Duration::from_secs(12),
                App::start(&config.text, Format::Json, Path::new("."), true),
            )
            .await
        });
        let app = match result {
            Ok(Ok(app)) => app,
            _ => {
                runtime.shutdown_timeout(Duration::from_secs(2));
                return Err("Core assembly failed or timed out".to_owned());
            }
        };
        // Upstream may swallow bind failures. Require this instance's bound port,
        // then a real SOCKS handshake; never accept an unrelated existing listener.
        let bound =
            app.listen_ports.len() == 1 && app.listen_ports.iter().any(|(_, p)| *p == config.port);
        if !bound || !socks_ready(config.port) {
            app.router.current().abort_background_tasks();
            app.conns.close_all();
            drop(app);
            runtime.shutdown_timeout(Duration::from_secs(2));
            return Err("Required mixed listener is not ready".to_owned());
        }
        Ok(Self {
            app,
            runtime,
            config,
        })
    }

    fn stop(self) {
        self.app.conns.close_all();
        self.app.router.current().abort_background_tasks();
        drop(self.app);
        // Runs outside Tokio. Runtime cancellation releases all listener sockets.
        self.runtime.shutdown_timeout(Duration::from_secs(2));
    }
}

fn socks_ready(port: u16) -> bool {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_secs(1)) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
    let mut response = [0u8; 2];
    stream.write_all(&[5, 1, 0]).is_ok()
        && stream.read_exact(&mut response).is_ok()
        && response == [5, 0]
}

#[derive(Default)]
pub struct Host {
    running: Option<Running>,
    generation: u64,
    failed: bool,
}

impl Host {
    pub fn request(&mut self, text: &str) -> Value {
        if text.len() > MAX_REQUEST_BYTES {
            return self.error("", "REQUEST_TOO_LARGE", "Request exceeds 1 MiB", None);
        }
        let req: Request = match serde_json::from_str(text) {
            Ok(req) => req,
            Err(_) => return self.error("", "INVALID_REQUEST", "Invalid request envelope", None),
        };
        if req.request_id.is_empty() || req.request_id.len() > 128 {
            return self.error("", "INVALID_REQUEST", "Invalid request ID", None);
        }
        let result = self.dispatch(&req);
        match result {
            Ok(value) => json!({
                "requestId": req.request_id, "ok": true,
                "generation": self.generation, "result": value,
            }),
            Err((code, message, rollback)) => self.error(&req.request_id, code, &message, rollback),
        }
    }

    fn error(&self, id: &str, code: &str, message: &str, rollback: Option<&str>) -> Value {
        json!({"requestId": id, "ok": false, "generation": self.generation,
            "error": {"code": code, "message": message, "rollbackStatus": rollback},
            "status": self.status()})
    }

    fn dispatch(
        &mut self,
        req: &Request,
    ) -> Result<Value, (&'static str, String, Option<&'static str>)> {
        if matches!(
            req.operation.as_str(),
            "start" | "apply" | "stop" | "quit" | "select"
        ) {
            let revision = self
                .running
                .as_ref()
                .map(|r| r.config.revision)
                .unwrap_or(0);
            if req.expected_generation != Some(self.generation)
                || req.expected_applied_revision != Some(revision)
            {
                return Err((
                    "STATE_CONFLICT",
                    "Host state changed; query before retrying".into(),
                    None,
                ));
            }
        }
        match req.operation.as_str() {
            "capabilities" => Ok(json!({
                "protocolVersion": PROTOCOL_VERSION,
                "coreCommit": CORE_COMMIT,
                "coreVersion": "1.1.0",
                "hostVersion": env!("CARGO_PKG_VERSION"),
                "coreBuildId": format!("{CORE_COMMIT}/flvp-host-{}+P001", env!("CARGO_PKG_VERSION")),
                "patches": ["P001-http-authority"],
                "ordinaryProxy": true, "vpn": false, "tun": false,
                "systemProxy": false, "subscriptionImport": false,
                "hotReload": false, "applyStrategy": "restart-with-rollback",
                "protocols": ["socks5", "http"],
                "ruleTypes": ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "NETWORK", "DST-PORT", "MATCH"]
            })),
            "status" => Ok(self.status()),
            "start" | "apply" => {
                let config = PreparedConfig::from_arguments(&req.arguments)
                    .map_err(|e| ("CONFIG_REJECTED", e, None))?;
                if req.operation == "start" && self.running.is_some() {
                    return Err(("ALREADY_RUNNING", "Core is already running".into(), None));
                }
                if req.operation == "apply" {
                    let Some(current) = self.running.as_ref() else {
                        return Err(("NOT_RUNNING", "Core is stopped".into(), None));
                    };
                    if config.revision <= current.config.revision {
                        return Err(("REVISION_CONFLICT", "Revision must increase".into(), None));
                    }
                }
                let previous = self.running.take().map(|running| {
                    let config = running.config.clone();
                    running.stop();
                    config
                });
                self.generation += 1;
                match Running::start(config) {
                    Ok(running) => {
                        self.running = Some(running);
                        self.failed = false;
                        Ok(self.status())
                    }
                    Err(error) => {
                        if let Some(previous) = previous {
                            self.generation += 1;
                            match Running::start(previous) {
                                Ok(restored) => {
                                    self.running = Some(restored);
                                    self.failed = false;
                                    Err(("APPLY_FAILED", error, Some("restored")))
                                }
                                Err(_) => {
                                    self.failed = true;
                                    Err(("ROLLBACK_FAILED", error, Some("failed")))
                                }
                            }
                        } else {
                            self.failed = true;
                            Err(("CORE_START_FAILED", error, None))
                        }
                    }
                }
            }
            "stop" | "quit" => {
                self.stop();
                Ok(self.status())
            }
            _ => Err((
                "UNSUPPORTED_OPERATION",
                "Operation is not supported".into(),
                None,
            )),
        }
    }

    pub fn status(&self) -> Value {
        if let Some(running) = &self.running {
            let stats = running.app.stats.snapshot();
            let router = running.app.router.current();
            let selected = router
                .get_group("PROXY")
                .map(|g| g.selected_name().to_string());
            json!({"state": "running", "generation": self.generation,
                "appliedRevision": running.config.revision, "configHash": running.config.hash,
                "mixedPort": running.config.port, "upload": stats.upload,
                "download": stats.download, "connections": running.app.conns.list().len(),
                "selected": selected})
        } else {
            json!({"state": if self.failed {"failed"} else {"stopped"},
                "generation": self.generation, "appliedRevision": 0,
                "configHash": null, "mixedPort": null,
                "upload": 0, "download": 0, "connections": 0, "selected": null})
        }
    }

    pub fn stop(&mut self) {
        if let Some(running) = self.running.take() {
            running.stop();
        }
        self.failed = false;
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        self.stop();
    }
}

pub fn init_logging() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let _ = tracing_subscriber::fmt()
            .with_env_filter("warn")
            .with_ansi(false)
            .with_writer(std::io::stderr)
            .try_init();
    });
}

fn global_request(text: &str) -> String {
    static HOST: OnceLock<Mutex<Host>> = OnceLock::new();
    init_logging();
    let result = std::panic::catch_unwind(|| {
        HOST.get_or_init(|| Mutex::new(Host::default()))
            .lock()
            .map(|mut host| host.request(text))
    });
    match result {
        Ok(Ok(value)) => value.to_string(),
        _ => json!({"requestId": "", "ok": false, "generation": 0,
            "error": {"code": "HOST_FAILURE", "message": "Native host failure; restart required"}})
        .to_string(),
    }
}

/// Host-owned result: the caller must release it with flvp_host_free_string.
/// # Safety
/// Input must point to a valid NUL-terminated UTF-8 buffer for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn flvp_host_request(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(text) = (unsafe { CStr::from_ptr(input) }).to_str() else {
        return std::ptr::null_mut();
    };
    CString::new(global_request(text))
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// Only pass NULL or a result returned by flvp_host_request, exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn flvp_host_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_flvpcore_app_CoreNative_request(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    input: jni::objects::JString,
) -> jni::sys::jstring {
    let text: String = match env.get_string(&input) {
        Ok(value) => value.into(),
        Err(_) => return std::ptr::null_mut(),
    };
    env.new_string(global_request(&text))
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};
    use std::net::TcpListener;

    fn port() -> u16 {
        TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port()
    }

    fn arguments(port: u16, revision: u64) -> Value {
        let text = json!({"mixed-port": port, "allow-lan": false,
            "bind-address": "127.0.0.1", "mode": "rule", "log-level": "warn",
            "ipv6": false, "dns": {"enable": false},
            "tun": {"enable": false, "auto-route": false},
            "proxies": [], "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": ["DIRECT"]}],
            "rules": ["MATCH,DIRECT"]}).to_string();
        let hash = format!("{:x}", Sha256::digest(text.as_bytes()));
        json!({"config": text, "configHash": hash, "revision": revision})
    }

    fn call(host: &mut Host, operation: &str, args: Value) -> Value {
        let revision = host.status()["appliedRevision"].as_u64().unwrap();
        host.request(
            &json!({"requestId":"test", "operation":operation,
            "expectedGeneration":host.generation, "expectedAppliedRevision":revision,
            "arguments":args})
            .to_string(),
        )
    }

    #[test]
    fn failed_bind_does_not_report_running() {
        let occupied = TcpListener::bind("127.0.0.1:0").unwrap();
        let p = occupied.local_addr().unwrap().port();
        let mut host = Host::default();
        let response = call(&mut host, "start", arguments(p, 1));
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], "CORE_START_FAILED");
        assert_ne!(host.status()["state"], "running");
    }

    #[test]
    fn apply_failure_restores_old_listener_and_revision() {
        let mut host = Host::default();
        let p = port();
        assert_eq!(call(&mut host, "start", arguments(p, 1))["ok"], true);
        let occupied = TcpListener::bind("127.0.0.1:0").unwrap();
        let response = call(
            &mut host,
            "apply",
            arguments(occupied.local_addr().unwrap().port(), 2),
        );
        assert_eq!(response["error"]["rollbackStatus"], "restored");
        assert_eq!(host.status()["appliedRevision"], 1);
        assert!(socks_ready(p));
        assert_eq!(call(&mut host, "stop", json!({}))["ok"], true);
        assert!(TcpListener::bind(("127.0.0.1", p)).is_ok());
    }

    #[test]
    fn rejects_stale_mutations_and_hash_mismatch() {
        let mut host = Host::default();
        let mut args = arguments(port(), 1);
        args["configHash"] = json!("incorrect");
        assert_eq!(
            call(&mut host, "start", args)["error"]["code"],
            "CONFIG_REJECTED"
        );
        let stale = host.request(r#"{"requestId":"stale","operation":"stop","expectedGeneration":9,"expectedAppliedRevision":0}"#);
        assert_eq!(stale["error"]["code"], "STATE_CONFLICT");
    }

    #[test]
    fn refuses_vpn_and_unknown_rules_before_start() {
        let args = arguments(port(), 1);
        let mut config: Value = serde_json::from_str(args["config"].as_str().unwrap()).unwrap();
        config["tun"]["enable"] = json!(true);
        assert!(config::validate(&config.to_string()).is_err());
        config["tun"]["enable"] = json!(false);
        config["rules"] = json!(["UNKNOWN,example.org,DIRECT", "MATCH,DIRECT"]);
        assert!(config::validate(&config.to_string()).is_err());
    }
}
