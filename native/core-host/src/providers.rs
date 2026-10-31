//! 把本地 rule-provider 文件注入内核配置。
//!
//! 内核的 `App::start` 自己会按 `rule-providers` 里的 `type: file` + `path`
//! 读取载荷（vp-app::load_providers），所以宿主只需要把索引换成内核认识的
//! 结构，不联网、也不让内核按 URL 自动更新。

use std::path::PathBuf;

use serde_json::{Map, Value};

struct Entry {
    name: String,
    behavior: String,
    path: PathBuf,
}

fn entries() -> Result<Vec<Entry>, String> {
    let mut out = Vec::new();
    let Some(base) = std::env::var_os("FLVP_APP_SUPPORT_DIR").map(PathBuf::from) else {
        return Ok(out);
    };
    let dir = base.join("providers");
    let index = dir.join("index.json");
    if !index.exists() {
        return Ok(out);
    }
    let raw = std::fs::read_to_string(&index)
        .map_err(|_| "Rule provider index is unreadable".to_owned())?;
    let value: Value = serde_json::from_str(raw.trim_start_matches('\u{feff}'))
        .map_err(|_| "Rule provider index is not valid JSON".to_owned())?;
    let items = value
        .get("providers")
        .and_then(|item| item.as_array())
        .ok_or_else(|| "Rule provider index is missing providers".to_owned())?;
    for item in items {
        let name = item
            .get("name")
            .and_then(|value| value.as_str())
            .ok_or_else(|| "Rule provider entry is missing name".to_owned())?;
        let behavior = item
            .get("behavior")
            .and_then(|value| value.as_str())
            .ok_or_else(|| format!("Rule provider {name} is missing behavior"))?;
        vp_rule::provider::Behavior::parse(behavior)
            .map_err(|error| format!("Rule provider {name}: {error}"))?;
        let file = item
            .get("file")
            .and_then(|value| value.as_str())
            .ok_or_else(|| format!("Rule provider {name} is missing file"))?;
        if file.contains('/') || file.contains('\\') || file.contains("..") {
            return Err(format!("Rule provider {name} has an unsafe file name"));
        }
        out.push(Entry {
            name: name.to_owned(),
            behavior: behavior.to_owned(),
            path: dir.join(file),
        });
    }
    Ok(out)
}

/// 返回注入了 `rule-providers` 的配置文本；没有本地 provider 时原样返回。
pub fn inject(text: &str) -> Result<String, String> {
    let entries = entries()?;
    if entries.is_empty() {
        return Ok(text.to_owned());
    }
    let mut value: Value = serde_json::from_str(text)
        .map_err(|_| "Core configuration is not valid JSON".to_owned())?;
    let mut providers = Map::new();
    for entry in entries {
        providers.insert(
            entry.name,
            serde_json::json!({
                "type": "file",
                "behavior": entry.behavior,
                "path": entry.path.to_string_lossy().replace('\\', "/"),
            }),
        );
    }
    match &mut value {
        Value::Object(map) => {
            map.insert("rule-providers".to_owned(), Value::Object(providers));
        }
        _ => return Err("Core configuration must be an object".to_owned()),
    }
    serde_json::to_string(&value).map_err(|_| "Core configuration serialization failed".to_owned())
}
