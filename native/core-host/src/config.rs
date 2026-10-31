use std::collections::{HashMap, HashSet};

use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

#[derive(Clone)]
pub struct PreparedConfig {
    pub text: String,
    pub hash: String,
    pub revision: u64,
    pub port: u16,
    pub tun_enabled: bool,
    pub tun_auto_route: bool,
    pub warnings: Vec<String>,
}

/// 配置被拒绝时携带的错误码，便于调用方区分「需要管理员」与其他拒绝。
pub struct Rejected {
    pub code: &'static str,
    pub message: String,
}

impl Rejected {
    fn config(message: String) -> Self {
        Self { code: "CONFIG_REJECTED", message }
    }
}

#[derive(Debug)]
pub struct Validated {
    pub port: u16,
    pub tun_enabled: bool,
    pub tun_auto_route: bool,
    pub warnings: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Arguments {
    config: String,
    config_hash: String,
    revision: u64,
}

impl PreparedConfig {
    pub fn from_arguments(value: &Value) -> Result<Self, Rejected> {
        let args: Arguments = serde_json::from_value(value.clone())
            .map_err(|_| Rejected::config("Invalid snapshot arguments".into()))?;
        let hash = format!("{:x}", Sha256::digest(args.config.as_bytes()));
        if args.revision == 0 || args.config_hash != hash {
            return Err(Rejected::config("Snapshot revision or SHA-256 is invalid".into()));
        }
        let validated = validate(&args.config).map_err(Rejected::config)?;
        if validated.tun_enabled && !crate::elevation::is_elevated() {
            return Err(Rejected {
                code: "TUN_REQUIRES_ADMIN",
                message: "TUN 需要管理员协助进程；请先安装并启动协助进程后重试".into(),
            });
        }
        let text = crate::providers::inject(&args.config).map_err(Rejected::config)?;
        Ok(Self {
            text,
            hash,
            revision: args.revision,
            port: validated.port,
            tun_enabled: validated.tun_enabled,
            tun_auto_route: validated.tun_auto_route,
            warnings: validated.warnings,
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
    dns: crate::dns::Dns,
    tun: Tun,
    proxies: Vec<Proxy>,
    proxy_groups: Vec<Group>,
    rules: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "kebab-case")]
struct Tun {
    #[serde(default)]
    enable: bool,
    #[serde(default)]
    auto_route: bool,
    #[serde(default)]
    address: Option<String>,
    #[serde(default)]
    netmask: Option<String>,
    #[serde(default)]
    mtu: Option<u16>,
    #[serde(default)]
    fake_ip_range: Option<String>,
    #[serde(default)]
    ring_capacity: Option<u32>,
    #[serde(default)]
    auto_redirect: Option<bool>,
    #[serde(flatten)]
    extra: serde_json::Map<String, Value>,
}

impl Tun {
    /// 校验 TUN 字段：内核支持的透传，常见但当前无实现的字段降级并提示，
    /// 未知字段显式报错而不是静默丢弃。
    fn plan(&self) -> Result<(bool, bool, Vec<String>), String> {
        let mut warnings = Vec::new();
        for key in self.extra.keys() {
            match key.as_str() {
                "stack"
                | "dns-hijack"
                | "auto-detect-interface"
                | "strict-route"
                | "device"
                | "gso"
                | "udp-timeout"
                | "endpoint-independent-nat" => {
                    warnings.push(format!("tun 字段 {key} 暂未接入，已忽略"));
                }
                other => return Err(format!("tun 字段 {other} 不受支持")),
            }
        }
        if let Some(mtu) = self.mtu
            && !(576..=9000).contains(&mtu)
        {
            return Err("tun.mtu 超出 576-9000".into());
        }
        if let Some(ring) = self.ring_capacity
            && (!ring.is_power_of_two() || !(131_072..=67_108_864).contains(&ring))
        {
            return Err("tun.ring-capacity 必须是 128KiB-64MiB 之间的 2 的幂".into());
        }
        if let Some(address) = &self.address {
            address
                .parse::<std::net::Ipv4Addr>()
                .map_err(|_| "tun.address 必须是 IPv4 地址".to_owned())?;
        }
        if let Some(netmask) = &self.netmask {
            netmask
                .parse::<std::net::Ipv4Addr>()
                .map_err(|_| "tun.netmask 必须是 IPv4 掩码".to_owned())?;
        }
        if let Some(range) = &self.fake_ip_range
            && !range.contains('/')
        {
            return Err("tun.fake-ip-range 必须是 CIDR".into());
        }
        Ok((self.enable, self.auto_route, warnings))
    }
}

#[derive(Deserialize)]
struct Proxy {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    server: String,
    port: u16,
    #[serde(flatten)]
    options: serde_json::Map<String, Value>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Group {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    proxies: Vec<String>,
    url: Option<String>,
    interval: Option<u64>,
    tolerance: Option<u32>,
    lazy: Option<bool>,
}

fn validate_groups(cfg: &OrdinaryConfig) -> Result<(), String> {
    let error = || "Invalid policy group, reference or health check parameters".to_owned();
    if cfg.proxy_groups.is_empty() || cfg.proxy_groups.len() > 65 {
        return Err(error());
    }
    let mut names: HashSet<&str> = ["DIRECT", "REJECT"].into_iter().collect();
    for node in &cfg.proxies {
        if !names.insert(&node.name) {
            return Err(error());
        }
    }
    for group in &cfg.proxy_groups {
        if !names.insert(&group.name)
            || (group.name != "PROXY"
                && (!group.name.starts_with("group_")
                    || group.name.len() > 80
                    || !group
                        .name
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'_')))
        {
            return Err(error());
        }
    }
    let by_name: HashMap<&str, &Group> = cfg
        .proxy_groups
        .iter()
        .map(|g| (g.name.as_str(), g))
        .collect();
    if by_name.get("PROXY").is_none_or(|g| g.kind != "select") {
        return Err(error());
    }
    for g in &cfg.proxy_groups {
        if g.proxies.is_empty()
            || g.proxies.len() > 1024
            || g.proxies.iter().collect::<HashSet<_>>().len() != g.proxies.len()
            || g.proxies.iter().any(|n| {
                !names.contains(n.as_str())
                    || n == "PROXY"
                    || (g.name == "PROXY" && by_name.contains_key(n.as_str()))
            })
        {
            return Err(error());
        }
        match g.kind.as_str() {
            "select" => {
                if g.url.is_some()
                    || g.interval.is_some()
                    || g.tolerance.is_some()
                    || g.lazy.is_some()
                {
                    return Err(error());
                }
            }
            "url-test" | "fallback" => {
                if g.lazy != Some(false)
                    || !g.interval.is_some_and(|i| (30..=86400).contains(&i))
                    || g.tolerance.is_some_and(|n| n > 60000)
                    || (g.kind == "fallback" && g.tolerance.is_some())
                {
                    return Err(error());
                }
                let url = g.url.as_deref().ok_or_else(error)?;
                if url.len() > 2048 || url.bytes().any(|b| b <= 32 || b == 127) || url.contains('#')
                {
                    return Err(error());
                }
                let (scheme, rest) = url.split_once("://").ok_or_else(error)?;
                if !matches!(scheme, "http" | "https") {
                    return Err(error());
                }
                let authority = rest.split('/').next().ok_or_else(error)?;
                if authority.is_empty() || authority.contains(['@', '[', ']', '?']) {
                    return Err(error());
                }
                let host = if let Some((host, port)) = authority.split_once(':') {
                    let port: u16 = port.parse().map_err(|_| error())?;
                    if port == 0 || (scheme == "http" && port == 443) {
                        return Err(error());
                    }
                    host
                } else {
                    authority
                };
                if host.is_empty()
                    || !host
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
                {
                    return Err(error());
                }
            }
            _ => return Err(error()),
        }
    }
    fn depth<'a>(
        name: &'a str,
        groups: &HashMap<&'a str, &'a Group>,
        visiting: &mut HashSet<&'a str>,
        depths: &mut HashMap<&'a str, usize>,
    ) -> Result<usize, String> {
        if let Some(n) = depths.get(name) {
            return Ok(*n);
        }
        if !visiting.insert(name) {
            return Err("Policy groups contain a cycle".into());
        }
        let mut height = 1;
        for child in &groups[name].proxies {
            if groups.contains_key(child.as_str()) {
                height = height.max(1 + depth(child, groups, visiting, depths)?);
            }
        }
        if height > 16 {
            return Err("Policy group nesting exceeds 16".into());
        }
        visiting.remove(name);
        depths.insert(name, height);
        Ok(height)
    }
    let mut depths = HashMap::new();
    for name in by_name.keys() {
        depth(name, &by_name, &mut HashSet::new(), &mut depths)?;
    }
    Ok(())
}

pub fn validate(text: &str) -> Result<Validated, String> {
    if text.len() > 1024 * 1024 {
        return Err("Runtime configuration exceeds 1 MiB".into());
    }
    let cfg: OrdinaryConfig = serde_json::from_str(text)
        .map_err(|_| "Configuration contains invalid or unsupported fields".to_owned())?;
    if cfg.mixed_port == 0
        || cfg.allow_lan
        || cfg.bind_address != "127.0.0.1"
        || cfg.mode != "rule"
        || cfg.log_level != "warn"
        || cfg.ipv6
    {
        return Err("Only loopback ordinary proxy mode is available in this build".into());
    }
    cfg.dns.validate()?;
    let (tun_enabled, tun_auto_route, mut warnings) = cfg.tun.plan()?;
    if cfg.proxies.len() > 1024 || cfg.rules.len() > 8192 {
        return Err("Configuration exceeds this milestone's resource limits".into());
    }
    for proxy in &cfg.proxies {
        crate::node_options::validate(&proxy.kind, &proxy.options)?;
        if proxy.port == 0
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
    validate_groups(&cfg)?;
    if cfg.rules.last().is_none_or(|r| !r.starts_with("MATCH,")) {
        return Err("An explicit final MATCH is required".into());
    }
    for (index, rule) in cfg.rules.iter().enumerate() {
        let fields: Vec<_> = rule.split(',').collect();
        let ty = fields[0];
        if (ty == "MATCH" && fields.len() != 2)
            || (ty != "MATCH"
                && fields.len() != 3
                && !((ty == "IP-CIDR" || ty == "GEOIP" || ty == "RULE-SET")
                    && fields.len() == 4
                    && fields[3] == "no-resolve"))
            || fields
                .iter()
                .any(|v| v.is_empty() || v.chars().any(char::is_whitespace))
        {
            return Err("Invalid rule fields or modifiers".into());
        }
        if !matches!(
            ty,
            "DOMAIN"
                | "DOMAIN-SUFFIX"
                | "DOMAIN-KEYWORD"
                | "IP-CIDR"
                | "NETWORK"
                | "DST-PORT"
                | "MATCH"
                | "GEOIP"
                | "GEOSITE"
                | "RULE-SET"
        ) || (ty == "MATCH" && index + 1 != cfg.rules.len())
        {
            return Err("Unknown, unsupported or unreachable rule".into());
        }
    }
    let geo = crate::geo::GeoData::load();
    for rule in &cfg.rules {
        let fields: Vec<_> = rule.split(',').collect();
        match fields[0] {
            "GEOIP" => {
                let Some(found) = geo.has_geoip(fields[1]) else {
                    return Err("GEOIP rules require geoip.dat in the data directory".into());
                };
                if !found {
                    return Err(format!("Unknown GEOIP category {}", fields[1]));
                }
            }
            "GEOSITE" => {
                let Some(found) = geo.has_geosite(fields[1]) else {
                    return Err("GEOSITE rules require geosite.dat in the data directory".into());
                };
                if !found {
                    return Err(format!("Unknown GEOSITE category {}", fields[1]));
                }
            }
            _ => {}
        }
    }
    let upstream = vp_config::parse_and_validate(text, vp_config::Format::Json)
        .map_err(|_| "Core configuration validation failed".to_owned())?;
    // Upstream normally constructs outbounds lazily. Check construction before
    // stopping the working runtime, without opening any remote connection.
    let deps = vp_protocol::OutboundDeps {
        dns: std::sync::Arc::new(vp_dns::Resolver::system()),
        ipv6: false,
    };
    for node in &upstream.proxies {
        vp_protocol::build_outbound_eager(node, &deps)
            .map_err(|_| "Core outbound preflight failed".to_owned())?;
    }
    let known = |name: &str| {
        name == "DIRECT"
            || name == "REJECT"
            || name == "PROXY"
            || cfg.proxy_groups.iter().any(|g| g.name == name)
            || cfg.proxies.iter().any(|proxy| proxy.name == name)
    };
    let providers = load_providers()?;
    vp_rule::compile(
        &upstream.rules,
        &vp_rule::CompileEnv {
            is_known_target: &known,
            geosite: &geo.geosite,
            geoip: &geo.geoip,
            asn: &None,
            providers: &providers,
            sub_rules: &HashMap::new(),
        },
    )
    .map_err(|errors| format!("Strict rule compilation failed: {}", errors.join("; ")))?;
    Ok(Validated {
        port: cfg.mixed_port,
        tun_enabled,
        tun_auto_route,
        warnings,
    })
}

fn load_providers() -> Result<HashMap<String, (vp_rule::provider::Behavior, String)>, String> {
    let mut providers = HashMap::new();
    let Some(base) = std::env::var_os("FLVP_APP_SUPPORT_DIR").map(std::path::PathBuf::from) else {
        return Ok(providers);
    };
    let dir = base.join("providers");
    let index = dir.join("index.json");
    if !index.exists() {
        return Ok(providers);
    }
    let raw = std::fs::read_to_string(&index)
        .map_err(|_| "Rule provider index is unreadable".to_owned())?;
    let value: serde_json::Value = serde_json::from_str(raw.trim_start_matches('\u{feff}'))
        .map_err(|_| "Rule provider index is not valid JSON".to_owned())?;
    let entries = value
        .get("providers")
        .and_then(|item| item.as_array())
        .ok_or_else(|| "Rule provider index is missing providers".to_owned())?;
    for entry in entries {
        let name = entry
            .get("name")
            .and_then(|item| item.as_str())
            .ok_or_else(|| "Rule provider entry is missing name".to_owned())?;
        let raw = entry
            .get("behavior")
            .and_then(|item| item.as_str())
            .ok_or_else(|| format!("Rule provider {name} is missing behavior"))?;
        let behavior = vp_rule::provider::Behavior::parse(raw)
            .map_err(|error| format!("Rule provider {name}: {error}"))?;
        let file = entry
            .get("file")
            .and_then(|item| item.as_str())
            .ok_or_else(|| format!("Rule provider {name} is missing file"))?;
        if file.contains('/') || file.contains('\\') || file.contains("..") {
            return Err(format!("Rule provider {name} has an unsafe file name"));
        }
        let payload = std::fs::read_to_string(dir.join(file))
            .map_err(|_| format!("Rule provider {name} payload is unreadable"))?;
        providers.insert(name.to_owned(), (behavior, payload));
    }
    Ok(providers)
}
