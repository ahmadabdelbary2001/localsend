// SPDX-License-Identifier: Apache-2.0
//
// Persisted list of received files (capped, newest first).
// Stored at ~/.config/localsend.ahmadabdelbary/history.json.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::platform::filesystem;

const MAX_ENTRIES: usize = 30;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub file_name: String,
    pub file_size: u64,
    pub path: Option<String>,
    pub sender_alias: String,
    /// Unix seconds.
    pub timestamp: u64,
    pub is_message: bool,
}

impl HistoryEntry {
    pub fn new(
        file_name: String,
        file_size: u64,
        path: Option<String>,
        sender_alias: String,
        is_message: bool,
    ) -> Self {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        Self {
            id: Uuid::new_v4().to_string(),
            file_name,
            file_size,
            path,
            sender_alias,
            timestamp,
            is_message,
        }
    }
}

pub struct HistoryService {
    state: Arc<Mutex<Vec<HistoryEntry>>>,
    path: PathBuf,
}

impl HistoryService {
    pub fn load_or_default() -> std::io::Result<Self> {
        let dir = filesystem::app_config_dir()
            .ok_or_else(|| std::io::Error::other("no config dir"))?;
        std::fs::create_dir_all(&dir)?;
        let path = dir.join("history.json");

        let state = if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str::<Vec<HistoryEntry>>(&s).ok())
                .unwrap_or_default()
        } else {
            Vec::new()
        };

        Ok(Self {
            state: Arc::new(Mutex::new(state)),
            path,
        })
    }

    pub fn snapshot(&self) -> Vec<HistoryEntry> {
        self.state.lock().map(|g| g.clone()).unwrap_or_default()
    }

    pub fn add(&self, entry: HistoryEntry) {
        {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            g.insert(0, entry);
            g.truncate(MAX_ENTRIES);
        }
        let _ = self.save();
    }

    pub fn remove(&self, id: &str) -> bool {
        let removed = {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            let before = g.len();
            g.retain(|e| e.id != id);
            g.len() != before
        };
        if removed {
            let _ = self.save();
        }
        removed
    }

    pub fn clear(&self) -> bool {
        let changed = {
            let mut g = match self.state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            let had = !g.is_empty();
            g.clear();
            had
        };
        if changed {
            let _ = self.save();
        }
        changed
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
