// SPDX-License-Identifier: Apache-2.0
//
// Persisted settings for the Ubuntu Touch frontend.
// Stored as JSON at ~/.config/localsend/settings.json.
//
// Rules:
//  - No Qt types.
//  - Synchronous API is deliberate: settings writes are ~1 KB and happen
//    only on user interaction. If this ever becomes hot, move the disk
//    write to a background task.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};

use crate::platform::filesystem;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct SettingsState {
    // identity
    pub alias: String,
    pub device_type: Option<String>,
    pub device_model: Option<String>,

    // appearance
    pub theme: String,        // "system" | "light" | "dark"
    pub color_mode: String,   // "system" | "localsend" | "oled" | "yaru" | "custom"
    pub custom_color: String, // "#RRGGBB"
    pub enable_animations: bool,
    pub advanced_settings: bool,

    // locale
    pub locale: Option<String>,

    // network
    pub port: u16,
    pub multicast_group: String,
    pub https: bool,
    pub discovery_timeout: u32,
    pub network_whitelist: Option<Vec<String>>,
    pub network_blacklist: Option<Vec<String>>,

    // receive
    pub quick_save: bool,
    pub quick_save_from_favorites: bool,
    pub receive_pin: Option<String>,
    pub auto_finish: bool,
    pub save_to_history: bool,
    pub verify_checksums: bool,
    pub destination: Option<String>,

    // send
    pub send_mode: String, // "single" | "multiple" | "link"
    pub create_checksums: bool,
    pub share_via_link_auto_accept: bool,
    pub receive_via_link_auto_accept: bool,
}

impl Default for SettingsState {
    fn default() -> Self {
        Self {
            alias: default_alias(),
            device_type: None,
            device_model: None,

            theme: "system".into(),
            color_mode: "localsend".into(),
            custom_color: "#009688".into(),
            enable_animations: true,
            advanced_settings: false,

            locale: None,

            port: 53317,
            multicast_group: "224.0.0.167".into(),
            https: true,
            discovery_timeout: 500,
            network_whitelist: None,
            network_blacklist: None,

            quick_save: false,
            quick_save_from_favorites: false,
            receive_pin: None,
            auto_finish: false,
            save_to_history: true,
            verify_checksums: false,
            destination: None,

            send_mode: "single".into(),
            create_checksums: false,
            share_via_link_auto_accept: false,
            receive_via_link_auto_accept: false,
        }
    }
}

/// TODO: use the same generator as app/lib/util/alias_generator.dart.
/// The Flutter frontend produces two-word aliases like "Cute Tomato".
fn default_alias() -> String {
    // Placeholder until we port alias_generator.dart.
    "LocalSend".to_string()
}

pub struct SettingsService {
    state: Arc<Mutex<SettingsState>>,
    path: PathBuf,
}

impl SettingsService {
    pub fn load_or_default() -> std::io::Result<Self> {
        let dir = filesystem::app_config_dir().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::NotFound, "no config dir available")
        })?;
        std::fs::create_dir_all(&dir)?;
        let path = dir.join("settings.json");

        let state = if path.exists() {
            match std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str::<SettingsState>(&s).ok())
            {
                Some(s) => s,
                None => {
                    log::warn!("settings.json unreadable, using defaults");
                    SettingsState::default()
                }
            }
        } else {
            SettingsState::default()
        };

        let svc = Self {
            state: Arc::new(Mutex::new(state)),
            path,
        };
        // Persist defaults on first launch so the file exists.
        if let Err(e) = svc.save() {
            log::warn!("initial settings save failed: {e}");
        }
        Ok(svc)
    }

    pub fn snapshot(&self) -> SettingsState {
        self.state.lock().map(|g| g.clone()).unwrap_or_default()
    }

    /// Update the state and persist.
    pub fn update<F>(&self, f: F)
    where
        F: FnOnce(&mut SettingsState),
    {
        {
            let mut guard = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            f(&mut guard);
        }
        if let Err(e) = self.save() {
            log::warn!("settings save failed: {e}");
        }
    }

    fn save(&self) -> std::io::Result<()> {
        let data = {
            let guard = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            serde_json::to_string_pretty(&*guard)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?
        };
        std::fs::write(&self.path, data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_matches_flutter_defaults() {
        let d = SettingsState::default();
        assert_eq!(d.port, 53317);
        assert_eq!(d.multicast_group, "224.0.0.167");
        assert_eq!(d.theme, "system");
        assert_eq!(d.color_mode, "localsend");
        assert!(d.enable_animations);
        assert!(!d.advanced_settings);
    }

    #[test]
    fn serde_roundtrip() {
        let d = SettingsState::default();
        let json = serde_json::to_string(&d).unwrap();
        let back: SettingsState = serde_json::from_str(&json).unwrap();
        assert_eq!(d.alias, back.alias);
        assert_eq!(d.port, back.port);
    }

    #[test]
    fn partial_json_uses_defaults() {
        let json = r#"{"alias":"Cute Tomato"}"#;
        let s: SettingsState = serde_json::from_str(json).unwrap();
        assert_eq!(s.alias, "Cute Tomato");
        assert_eq!(s.port, 53317); // default preserved
    }
}