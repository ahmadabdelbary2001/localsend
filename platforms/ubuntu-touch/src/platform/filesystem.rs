// SPDX-License-Identifier: Apache-2.0
//
// Confined filesystem access for Ubuntu Touch.
// Only the app's own directories are guaranteed writable.

use std::path::PathBuf;

pub fn app_config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".config")))
        .map(|p| p.join("localsend"))
}

pub fn app_data_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".local/share")))
        .map(|p| p.join("localsend"))
}

pub fn app_cache_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".cache")))
        .map(|p| p.join("localsend"))
}

fn dirs_home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Ensure standard dirs exist. Call once at startup.
pub fn ensure_dirs() -> std::io::Result<()> {
    for d in [app_config_dir(), app_data_dir(), app_cache_dir()].into_iter().flatten() {
        std::fs::create_dir_all(d)?;
    }
    Ok(())
}