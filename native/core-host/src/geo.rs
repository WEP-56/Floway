//! Geo 资源加载：只读本地数据目录，不跟随 URL 自行下载，避免内核在后台
//! 改变规则语义。缺少文件或类别时由 `config` 层的预检直接拒绝，而不是让
//! 内核静默跳过规则。

use std::path::{Path, PathBuf};

pub struct GeoData {
    pub geosite: Option<vp_rule::geosite::GeoSiteDb>,
    pub geoip: Option<vp_rule::geoip::GeoIpDb>,
}

impl GeoData {
    /// 优先 `FLVP_GEO_DIR`，否则用应用数据目录下的 `geo/`。
    pub fn load() -> Self {
        let dir = std::env::var_os("FLVP_GEO_DIR")
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("FLVP_APP_SUPPORT_DIR")
                    .map(|base| PathBuf::from(base).join("geo"))
            });
        match dir {
            Some(dir) => Self::load_from(&dir),
            None => Self {
                geosite: None,
                geoip: None,
            },
        }
    }

    pub fn load_from(dir: &Path) -> Self {
        let geosite = vp_rule::geosite::GeoSiteDb::load_file(&dir.join("geosite.dat")).ok();
        let geoip = vp_rule::geoip::GeoIpDb::load(&dir.join("geoip.dat")).ok();
        Self { geosite, geoip }
    }

    /// `None` 表示数据库未加载；`Some(false)` 表示数据库里没有该类别。
    pub fn has_geosite(&self, tag: &str) -> Option<bool> {
        self.geosite.as_ref().map(|db| db.has(tag))
    }

    pub fn has_geoip(&self, code: &str) -> Option<bool> {
        self.geoip
            .as_ref()
            .map(|db| db.matcher(code.to_string()).is_some())
    }
}
