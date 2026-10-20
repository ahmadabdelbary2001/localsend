// SPDX-License-Identifier: Apache-2.0
//
// Persisted list of favorite devices.
// Stored at ~/.config/localsend.ahmadabdelbary/favorites.json.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::platform::filesystem;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Favorite {
    pub id: String,
    pub fingerprint: String,
    pub ip: String,
    pub port: u16,
    pub alias: String,
    pub custom_alias: bool,
}

impl Favorite {
    pub fn new(fingerprint: String, ip: String, port: u16, alias: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            fingerprint,
            ip,
            port,
            alias,
            custom_alias: false,
        }
    }
}

pub struct FavoritesService {
    state: Arc<Mutex<Vec<Favorite>>>,
    path: PathBuf,
}

impl FavoritesService {
    pub fn load_or_default() -> std::io::Result<Self> {
        let dir =
            filesystem::app_config_dir().ok_or_else(|| std::io::Error::other("no config dir"))?;
        std::fs::create_dir_all(&dir)?;
        let path = dir.join("favorites.json");

        let state = if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str::<Vec<Favorite>>(&s).ok())
                .unwrap_or_default()
        } else {
            Vec::new()
        };

        Ok(Self {
            state: Arc::new(Mutex::new(state)),
            path,
        })
    }

    pub fn snapshot(&self) -> Vec<Favorite> {
        self.state.lock().map(|g| g.clone()).unwrap_or_default()
    }

    /// Adds a new favorite. Returns false if the fingerprint already exists.
    pub fn add(&self, fav: Favorite) -> bool {
        let mut g = match self.state.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        if g.iter().any(|f| f.fingerprint == fav.fingerprint) {
            return false;
        }
        g.push(fav);
        drop(g);
        let _ = self.save();
        true
    }

    /// Updates alias of a favorite, setting custom_alias=true.
    pub fn update_alias(&self, fingerprint: &str, alias: String) -> bool {
        let mut changed = false;
        {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            if let Some(f) = g.iter_mut().find(|f| f.fingerprint == fingerprint) {
                f.alias = alias;
                f.custom_alias = true;
                changed = true;
            }
        }
        if changed {
            let _ = self.save();
        }
        changed
    }

    pub fn remove_by_fingerprint(&self, fingerprint: &str) -> bool {
        let removed = {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            let before = g.len();
            g.retain(|f| f.fingerprint != fingerprint);
            g.len() != before
        };
        if removed {
            let _ = self.save();
        }
        removed
    }

    pub fn is_favorite(&self, fingerprint: &str) -> bool {
        self.state
            .lock()
            .map(|g| g.iter().any(|f| f.fingerprint == fingerprint))
            .unwrap_or(false)
    }

    pub fn find(&self, fingerprint: &str) -> Option<Favorite> {
        self.state
            .lock()
            .ok()
            .and_then(|g| g.iter().find(|f| f.fingerprint == fingerprint).cloned())
    }

    fn save(&self) -> std::io::Result<()> {
        let data = {
            let g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            serde_json::to_string_pretty(&*g).map_err(std::io::Error::other)?
        };
        std::fs::write(&self.path, data)
    }
}
