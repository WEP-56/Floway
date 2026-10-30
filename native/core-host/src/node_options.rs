//! Host-side protocol boundary; mirrors the typed client model, not upstream's
//! permissive deserializer. Errors must never include credentials or addresses.
use serde::Deserialize;
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};

#[derive(Deserialize, Default)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
struct Options {
    username: Option<String>,
    password: Option<String>,
    uuid: Option<String>,
    cipher: Option<String>,
    #[serde(rename = "alterId")]
    alter_id: Option<u32>,
    tls: Option<bool>,
    sni: Option<String>,
    skip_cert_verify: Option<bool>,
    client_fingerprint: Option<String>,
    udp: Option<bool>,
    network: Option<String>,
    flow: Option<String>,
    alpn: Option<Vec<String>>,
    ws_opts: Option<Ws>,
    reality_opts: Option<Reality>,
    auth_str: Option<String>,
    up: Option<u32>,
    down: Option<u32>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Ws {
    path: String,
    headers: HashMap<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
struct Reality {
    public_key: String,
    short_id: String,
}

fn check(ok: bool) -> Result<(), String> {
    if ok {
        Ok(())
    } else {
        Err("Invalid or unsupported protocol parameters".into())
    }
}

fn clean(s: &str) -> bool {
    s.len() <= 4096 && !s.bytes().any(|b| b < 32 || b == 127)
}

pub fn validate(kind: &str, fields: &Map<String, Value>) -> Result<(), String> {
    let tls = ["sni", "skip-cert-verify"];
    let stream = [
        "tls",
        "client-fingerprint",
        "network",
        "alpn",
        "ws-opts",
        "udp",
        "sni",
        "skip-cert-verify",
    ];
    let mut allowed: Vec<&str> = match kind {
        "http" => vec!["username", "password", "tls", "sni", "skip-cert-verify"],
        "socks5" => vec!["username", "password", "udp"],
        "ss" => vec!["password", "cipher", "udp"],
        "vmess" => vec!["uuid", "cipher", "alterId"],
        "vless" => vec!["uuid", "flow", "reality-opts"],
        "trojan" => vec!["password"],
        "anytls" => vec!["password", "client-fingerprint", "udp"],
        "hysteria" => vec!["auth-str", "up", "down", "alpn"],
        "hysteria2" => vec!["password"],
        _ => return check(false),
    };
    if matches!(kind, "vmess" | "vless" | "trojan") {
        allowed.extend(stream);
    }
    if matches!(kind, "anytls" | "hysteria" | "hysteria2") {
        allowed.extend(tls);
    }
    check(
        fields
            .iter()
            .all(|(key, value)| allowed.contains(&key.as_str()) && !value.is_null()),
    )?;
    let o: Options = serde_json::from_value(Value::Object(fields.clone()))
        .map_err(|_| "Invalid protocol field types".to_owned())?;
    // Reading the bool is deliberate: serde checks its exact type even though
    // both values are supported. UDP availability is separate from TUN support.
    let _udp = o.udp;
    for value in [
        &o.username,
        &o.password,
        &o.uuid,
        &o.cipher,
        &o.sni,
        &o.client_fingerprint,
        &o.network,
        &o.flow,
        &o.auth_str,
    ]
    .into_iter()
    .flatten()
    {
        check(clean(value))?;
    }
    if matches!(kind, "http" | "socks5") {
        check(o.username.is_some() == o.password.is_some())?;
        if let (Some(u), Some(p)) = (&o.username, &o.password) {
            check(!u.is_empty() && !p.is_empty())?;
            check(kind != "http" || !u.contains(':'))?;
            check(kind != "socks5" || (u.len() <= 255 && p.len() <= 255))?;
        }
    }
    if matches!(kind, "ss" | "trojan" | "anytls" | "hysteria2") {
        check(o.password.as_ref().is_some_and(|p| !p.is_empty()))?;
    }
    if matches!(kind, "vmess" | "vless") {
        check(o.uuid.as_ref().is_some_and(|s| {
            s.len() == 36
                && s.bytes().enumerate().all(|(i, b)| {
                    if [8, 13, 18, 23].contains(&i) {
                        b == b'-'
                    } else {
                        b.is_ascii_hexdigit()
                    }
                })
        }))?;
    }
    if kind == "ss" {
        check(matches!(
            o.cipher.as_deref(),
            Some("aes-128-gcm" | "aes-256-gcm" | "chacha20-ietf-poly1305")
        ))?;
    }
    if kind == "vmess" {
        check(o.alter_id.is_none_or(|id| id == 0))?;
        check(matches!(
            o.cipher.as_deref(),
            None | Some("auto" | "aes-128-gcm" | "chacha20-poly1305" | "none" | "zero")
        ))?;
    }
    let uses_tls = o.tls.unwrap_or(matches!(
        kind,
        "trojan" | "anytls" | "hysteria" | "hysteria2"
    ));
    check(
        uses_tls
            || (o.sni.is_none()
                && o.skip_cert_verify != Some(true)
                && o.client_fingerprint.is_none()
                && o.alpn.is_none()
                && o.reality_opts.is_none()),
    )?;
    if let Some(s) = &o.sni {
        check(
            !s.is_empty()
                && s.len() <= 253
                && s.as_bytes()[0].is_ascii_alphanumeric()
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-'),
        )?;
    }
    check(
        o.client_fingerprint.is_none()
            || (o.client_fingerprint.as_deref() == Some("chrome") && o.reality_opts.is_some()),
    )?;
    check(matches!(o.network.as_deref(), None | Some("tcp" | "ws")))?;
    if let Some(ws) = &o.ws_opts {
        check(o.network.as_deref() == Some("ws"))?;
        check(
            ws.path.starts_with('/')
                && ws.path.len() <= 2048
                && !ws.path.bytes().any(|b| b <= 32 || b == 127),
        )?;
        check(ws.headers.len() <= 32)?;
        let mut names = HashSet::new();
        for (key, value) in &ws.headers {
            check(
                !key.is_empty()
                    && key
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+.^_`|~-".contains(&b))
                    && clean(value),
            )?;
            let key = key.to_ascii_lowercase();
            check(
                ![
                    "connection",
                    "upgrade",
                    "sec-websocket-key",
                    "sec-websocket-version",
                    "content-length",
                    "transfer-encoding",
                ]
                .contains(&key.as_str())
                    && names.insert(key),
            )?;
        }
    }
    check(matches!(
        o.flow.as_deref(),
        None | Some("" | "xtls-rprx-vision")
    ))?;
    if o.flow.as_deref() == Some("xtls-rprx-vision") {
        check(uses_tls && matches!(o.network.as_deref(), None | Some("tcp")))?;
    }
    if let Some(r) = &o.reality_opts {
        check(matches!(o.network.as_deref(), None | Some("tcp")))?;
        check(
            (r.public_key.len() == 43 || (r.public_key.len() == 44 && r.public_key.ends_with('=')))
                && r.public_key.as_bytes()[..43]
                    .iter()
                    .all(|b| b.is_ascii_alphanumeric() || *b == b'_' || *b == b'-'),
        )?;
        check(
            r.short_id.len() <= 16
                && r.short_id.len() % 2 == 0
                && r.short_id.bytes().all(|b| b.is_ascii_hexdigit()),
        )?;
    }
    if let Some(alpn) = &o.alpn {
        check(
            !alpn.is_empty()
                && alpn.len() <= 16
                && alpn.iter().all(|s| {
                    !s.is_empty() && s.len() <= 255 && !s.bytes().any(|b| b <= 32 || b == 127)
                }),
        )?;
    }
    if kind == "hysteria" {
        check(o.auth_str.as_ref().is_some_and(|s| {
            !s.trim().is_empty()
                && !["str", "base64"].contains(&s.trim().to_ascii_lowercase().as_str())
        }))?;
        check(
            [o.up, o.down]
                .iter()
                .all(|n| n.is_some_and(|n| (1..=1_000_000).contains(&n))),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn accepts(kind: &str, fields: Value) -> bool {
        validate(kind, fields.as_object().unwrap()).is_ok()
    }

    #[test]
    fn authentication_and_transport_boundaries() {
        assert!(accepts(
            "http",
            json!({"username":"u", "password":"p", "tls":true, "sni":"example.test"})
        ));
        for fields in [
            json!({"username":"u"}),
            json!({"password":null}),
            json!({"password":"p", "username":"u\r\n"}),
            json!({"ports":"1-100"}),
            json!({"tls":false,"sni":"example.test"}),
            json!({"tls":"true"}),
        ] {
            assert!(!accepts("http", fields));
        }
        assert!(!accepts(
            "socks5",
            json!({"username":"u", "password":"x".repeat(256)})
        ));
        assert!(!accepts(
            "hysteria2",
            json!({"password":"p", "mport":"100-200"})
        ));
        assert!(!accepts(
            "anytls",
            json!({"password":"p", "client-fingerprint":"chrome"})
        ));
    }

    #[test]
    fn advanced_protocols_reject_ignored_parameters() {
        let uuid = "11111111-1111-4111-8111-111111111111";
        assert!(accepts(
            "vless",
            json!({"uuid":uuid, "tls":true, "network":"ws", "ws-opts":{"path":"/t", "headers":{"Host":"example.test"}}})
        ));
        assert!(!accepts(
            "vless",
            json!({"uuid":uuid, "tls":true, "client-fingerprint":"ios"})
        ));
        assert!(!accepts(
            "vless",
            json!({"uuid":uuid, "tls":true, "flow":"xtls-rprx-vision", "network":"ws"})
        ));
        assert!(!accepts("vmess", json!({"uuid":uuid, "alterId":1})));
        assert!(!accepts("ss", json!({"password":"p", "cipher":"typo"})));
        assert!(accepts(
            "hysteria",
            json!({"auth-str":"p", "up":10, "down":20})
        ));
        assert!(!accepts(
            "hysteria",
            json!({"auth-str":"base64", "up":10, "down":20})
        ));
    }
}
