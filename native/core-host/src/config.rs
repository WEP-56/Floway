use std::collections::HashMap;

use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

#[derive(Clone)]
pub struct PreparedConfig {
    pub text: String,
    pub hash: String,
    pub revision: u64,
    pub port: u16,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Arguments {
    config: String,
    config_hash: String,
    revision: u64,
}

impl PreparedConfig {
    pub fn from_arguments(value: &Value) -> Result<Self, String> {
        let args: Arguments = serde_json::from_value(value.clone())
            .map_err(|_| "Invalid snapshot arguments".to_owned())?;
        let hash = format!("{:x}", Sha256::digest(args.config.as_bytes()));
        if args.revision == 0 || args.config_hash != hash {
            return Err("Snapshot revision or SHA-256 is invalid".into());
        }
        let port = validate(&args.config)?;
        Ok(Self {
            text: args.config,
            hash,
            revision: args.revision,
            port,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
struct OrdinaryConfig {
    mixed_port: u16,
    allow_lan: bool,
    bind_address: String,
    mode: String,
    log_level: String,
    ipv6: bool,
    dns: Dns,
    tun: Tun,
    proxies: Vec<Proxy>,
    proxy_groups: Vec<Group>,
    rules: Vec<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Dns {
    enable: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
struct Tun {
    enable: bool,
    auto_route: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Proxy {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    server: String,
    port: u16,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Group {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    proxies: Vec<String>,
}

pub fn validate(text: &str) -> Result<u16, String> {
    let cfg: OrdinaryConfig = serde_json::from_str(text)
        .map_err(|_| "Configuration contains invalid or unsupported fields".to_owned())?;
    if cfg.mixed_port == 0
        || cfg.allow_lan
        || cfg.bind_address != "127.0.0.1"
        || cfg.mode != "rule"
        || cfg.log_level != "warn"
        || cfg.ipv6
        || cfg.dns.enable
        || cfg.tun.enable
        || cfg.tun.auto_route
    {
        return Err("Only loopback ordinary proxy mode is available in this build".into());
    }
    if cfg.proxies.len() > 256 || cfg.rules.len() > 4096 {
        return Err("Configuration exceeds this milestone's resource limits".into());
    }
    for proxy in &cfg.proxies {
        if !matches!(proxy.kind.as_str(), "socks5" | "http")
            || proxy.port == 0
            || !proxy.name.starts_with("node_")
            || proxy.name.len() > 80
            || !proxy
                .name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
            || proxy.server.is_empty()
            || proxy.server.len() > 253
            || proxy
                .server
                .chars()
                .any(|c| c.is_whitespace() || c == '/' || c == '\\')
        {
            return Err("Invalid or unsupported proxy node".into());
        }
    }
    if cfg.proxy_groups.len() != 1
        || cfg.proxy_groups[0].name != "PROXY"
        || cfg.proxy_groups[0].kind != "select"
        || cfg.proxy_groups[0].proxies.is_empty()
    {
        return Err("Exactly one non-empty PROXY selector is required".into());
    }
    if cfg.rules.last().is_none_or(|r| !r.starts_with("MATCH,")) {
        return Err("An explicit final MATCH is required".into());
    }
    for (index, rule) in cfg.rules.iter().enumerate() {
        let ty = rule.split(',').next().unwrap_or("");
        if !matches!(
            ty,
            "DOMAIN"
                | "DOMAIN-SUFFIX"
                | "DOMAIN-KEYWORD"
                | "IP-CIDR"
                | "NETWORK"
                | "DST-PORT"
                | "MATCH"
        ) || (ty == "MATCH" && index + 1 != cfg.rules.len())
        {
            return Err("Unknown, unsupported or unreachable rule".into());
        }
    }
    let upstream = vp_config::parse_and_validate(text, vp_config::Format::Json)
        .map_err(|_| "Core configuration validation failed".to_owned())?;
    let known = |name: &str| {
        name == "DIRECT"
            || name == "REJECT"
            || name == "PROXY"
            || cfg.proxies.iter().any(|proxy| proxy.name == name)
    };
    vp_rule::compile(
        &upstream.rules,
        &vp_rule::CompileEnv {
            is_known_target: &known,
            geosite: &None,
            geoip: &None,
            asn: &None,
            providers: &HashMap::new(),
            sub_rules: &HashMap::new(),
        },
    )
    .map_err(|_| "Strict rule compilation failed".to_owned())?;
    Ok(cfg.mixed_port)
}
