use std::collections::HashSet;
use std::net::{IpAddr, Ipv4Addr};

use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub struct Dns {
    enable: bool,
    ipv6: Option<bool>,
    enhanced_mode: Option<String>,
    #[serde(default)]
    nameserver: Vec<String>,
    #[serde(default)]
    fallback: Vec<String>,
    fallback_filter: Option<Filter>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Filter {
    geoip: bool,
    #[serde(default)]
    ipcidr: Vec<String>,
    #[serde(default)]
    domain: Vec<String>,
}

impl Dns {
    pub fn validate(&self) -> Result<(), String> {
        let error = || "Invalid or unsupported ordinary proxy DNS settings".to_owned();
        if !self.enable {
            if self.ipv6.is_some()
                || self.enhanced_mode.is_some()
                || !self.nameserver.is_empty()
                || !self.fallback.is_empty()
                || self.fallback_filter.is_some()
            {
                return Err(error());
            }
            return Ok(());
        }
        if self.ipv6 == Some(true)
            || self
                .enhanced_mode
                .as_deref()
                .is_some_and(|m| m != "redir-host")
            || self.nameserver.is_empty()
        {
            return Err(error());
        }
        for list in [&self.nameserver, &self.fallback] {
            if list.len() > 16 || list.iter().collect::<HashSet<_>>().len() != list.len() {
                return Err(error());
            }
            for server in list {
                validate_server(server).map_err(|_| error())?;
            }
        }
        if let Some(f) = &self.fallback_filter {
            if f.geoip
                || self.fallback.is_empty()
                || f.ipcidr.len() > 64
                || f.domain.len() > 64
                || f.ipcidr.iter().collect::<HashSet<_>>().len() != f.ipcidr.len()
                || f.domain.iter().collect::<HashSet<_>>().len() != f.domain.len()
            {
                return Err(error());
            }
            for cidr in &f.ipcidr {
                let (address, prefix) = cidr.split_once('/').ok_or_else(error)?;
                let ip: IpAddr = address.parse().map_err(|_| error())?;
                let prefix: u8 = prefix.parse().map_err(|_| error())?;
                if prefix > if ip.is_ipv4() { 32 } else { 128 } {
                    return Err(error());
                }
            }
            for domain in &f.domain {
                if !domain.strip_prefix("+.").is_some_and(valid_host) {
                    return Err(error());
                }
            }
        }
        Ok(())
    }
}

fn valid_host(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= 253
        && host.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && label.as_bytes()[0].is_ascii_alphanumeric()
                && label.as_bytes()[label.len() - 1].is_ascii_alphanumeric()
                && label
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        })
}

fn validate_server(server: &str) -> Result<(), ()> {
    if server.is_empty()
        || server.len() > 2048
        || server.bytes().any(|b| !(33..127).contains(&b))
        || server.contains(['?', '#', '@', '\\'])
    {
        return Err(());
    }
    let (scheme, rest) = server.split_once("://").unwrap_or(("udp", server));
    if !matches!(scheme, "udp" | "tcp" | "tls" | "https") {
        return Err(());
    }
    let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
    if scheme != "https" && rest.contains('/') {
        return Err(());
    }
    let host = if let Some((host, port)) = authority.split_once(':') {
        if port.is_empty() || !port.bytes().all(|b| b.is_ascii_digit()) {
            return Err(());
        }
        let port: u16 = port.parse().map_err(|_| ())?;
        if port == 0 {
            return Err(());
        }
        host
    } else {
        authority
    };
    if !valid_host(host) {
        return Err(());
    }
    if scheme != "https" && host.parse::<Ipv4Addr>().is_err() {
        return Err(());
    }
    let _ = path;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    fn valid(value: Value) -> bool {
        serde_json::from_value::<Dns>(value).is_ok_and(|dns| dns.validate().is_ok())
    }

    #[test]
    fn supported_resolver_and_filter_settings() {
        assert!(valid(json!({"enable": false})));
        assert!(valid(
            json!({"enable": true, "ipv6": false, "enhanced-mode": "redir-host",
            "nameserver": ["223.5.5.5", "udp://127.0.0.1:5353", "tcp://1.1.1.1:53", "tls://1.1.1.1", "https://dns.example.test/dns-query"],
            "fallback": ["127.0.0.1:5354"], "fallback-filter": {"geoip": false,
                "ipcidr": ["240.0.0.0/4", "2001:db8::/32"], "domain": ["+.example.test"]}})
        ));
    }

    #[test]
    fn refuses_ignored_invalid_and_unsupported_semantics() {
        for server in [
            "tls://dns.example.test",
            "https://dns.example.test#insecure",
            "https://dns.example.test?q=1",
            "udp://127.0.0.1/",
            "https://a..test/x",
            "UDP://1.1.1.1",
            "127.0.0.1:0",
            "127.0.0.1:65536",
            "127.0.0.1:",
            "quic://1.1.1.1",
            "[::1]:53",
            "https://u:p@a.test/x",
        ] {
            assert!(!valid(json!({"enable": true, "nameserver": [server]})));
        }
        for dns in [
            json!({"enable": true, "nameserver": []}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "ipv6": true}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "enhanced-mode": "fake-ip"}),
            json!({"enable": false, "nameserver": ["1.1.1.1"]}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "respect-rules": false}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "listen": "127.0.0.1:53"}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "fallback": ["8.8.8.8"], "fallback-filter": {"geoip": true}}),
            json!({"enable": true, "nameserver": ["1.1.1.1"], "fallback-filter": {"geoip": false}}),
        ] {
            assert!(!valid(dns));
        }
    }
}
