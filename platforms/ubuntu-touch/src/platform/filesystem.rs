// SPDX-License-Identifier: Apache-2.0
//
// Confined filesystem access for Ubuntu Touch.
// Click confinement grants private writable XDG directories beneath the
// click package name declared in manifest.json.

use std::path::PathBuf;

const APP_PKGNAME: &str = "localsend.ahmadabdelbary";

fn app_specific_dir(base: PathBuf) -> PathBuf {
    base.join(APP_PKGNAME)
}

pub fn app_config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".config")))
        .map(app_specific_dir)
}

pub fn app_data_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".local/share")))
        .map(app_specific_dir)
}

pub fn app_cache_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs_home().map(|h| h.join(".cache")))
        .map(app_specific_dir)
}

fn dirs_home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

/// Ensure standard app-private dirs exist. Call once at startup.
pub fn ensure_dirs() -> std::io::Result<()> {
    for d in [app_config_dir(), app_data_dir(), app_cache_dir()].into_iter().flatten() {
        std::fs::create_dir_all(d)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_paths_use_the_click_package_name() {
        let base = PathBuf::from("/home/phablet/.config");
        assert_eq!(
            app_specific_dir(base),
            PathBuf::from("/home/phablet/.config/localsend.ahmadabdelbary")
        );
    }
}
