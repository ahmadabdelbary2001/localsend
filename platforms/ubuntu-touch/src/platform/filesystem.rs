// SPDX-License-Identifier: Apache-2.0
//
// Confined filesystem access for Ubuntu Touch.
// Click confinement grants private writable XDG directories beneath the
// click package name declared in manifest.json. Everything else is read-only
// unless the AppArmor profile asks for it explicitly: the click declares
// `write_path` for ~/Downloads and `read_path` for the home folder
// (see apparmor/localsend.apparmor). Receiving therefore writes straight into
// the user visible `~/Downloads/LocalSend` folder.

use std::path::{Path, PathBuf};

const APP_PKGNAME: &str = "localsend.ahmadabdelbary";

/// Folder name used inside the user's Downloads directory.
const RECEIVE_FOLDER_NAME: &str = "LocalSend";

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
    for d in [app_config_dir(), app_data_dir(), app_cache_dir()]
        .into_iter()
        .flatten()
    {
        std::fs::create_dir_all(d)?;
    }
    Ok(())
}

/// The visible receive folder, `~/Downloads/LocalSend`.
///
/// Writable because the click's AppArmor profile grants `write_path` for
/// `~/Downloads/` (`apparmor/localsend.apparmor`). Profiles installed before
/// that entry do not allow it, so this stays a preference, not a guarantee:
/// `resolve_receive_dir` probes and falls back when the path is not writable.
pub fn preferred_receive_dir() -> Option<PathBuf> {
    dirs_home().map(|home| home.join("Downloads").join(RECEIVE_FOLDER_NAME))
}

/// Guaranteed-writable receive folder: `<app data>/received`.
pub fn private_receive_dir() -> PathBuf {
    app_data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp/localsend-received"))
        .join("received")
}

/// Creates `dir` (and its parents) and verifies that files can actually be
/// written into it.
///
/// `create_dir_all` alone is not enough: on Ubuntu Touch `~/Downloads` exists
/// but AppArmor denies writes to it, and an existing directory makes
/// `create_dir_all` succeed. Probing with a real file is what catches that.
pub fn ensure_writable_dir(dir: &Path) -> bool {
    if std::fs::create_dir_all(dir).is_err() {
        return false;
    }
    let probe = dir.join(".localsend-write-test");
    match std::fs::write(&probe, b"") {
        Ok(()) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

/// Resolves where received files are stored, in order of preference:
///
/// 1. the folder the user configured (explicit choice wins),
/// 2. `~/Downloads/LocalSend` (the Ubuntu Touch default),
/// 3. the app-private `received` folder (last-resort fallback).
///
/// A candidate is only used when a real write probe succeeds, so receiving can
/// never fail because of an unreadable/unwritable destination.
pub fn resolve_receive_dir(configured: Option<&str>) -> PathBuf {
    let candidates = receive_candidates(configured);
    let private = private_receive_dir();

    match resolve_first_writable(&candidates) {
        Some(dir) => {
            if dir != private {
                log::debug!("receiving into {}", dir.display());
            } else {
                log::warn!(
                    "no user-visible receive folder is writable, receiving into {}",
                    dir.display()
                );
            }
            dir
        }
        None => {
            if let Err(error) = std::fs::create_dir_all(&private) {
                log::error!("cannot create {}: {error}", private.display());
            }
            private
        }
    }
}

/// Candidate folders for received files, in the order they are probed.
pub fn receive_candidates(configured: Option<&str>) -> Vec<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();

    // An explicitly configured folder is what the user asked for, so it wins
    // over the default. It is still probed: AppArmor may deny it.
    if let Some(dir) = configured.map(str::trim).filter(|d| !d.is_empty()) {
        candidates.push(PathBuf::from(dir));
    }
    if let Some(preferred) = preferred_receive_dir() {
        if !candidates.contains(&preferred) {
            candidates.push(preferred);
        }
    }
    let private = private_receive_dir();
    if !candidates.contains(&private) {
        candidates.push(private);
    }
    candidates
}

/// First candidate that accepts writes. Each candidate is created if needed.
fn resolve_first_writable(candidates: &[PathBuf]) -> Option<PathBuf> {
    candidates
        .iter()
        .find(|dir| ensure_writable_dir(dir))
        .cloned()
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

    #[test]
    fn preferred_receive_dir_is_downloads_localsend() {
        // The test environment always has HOME set (cargo sets it on Unix).
        let home = dirs_home().expect("HOME");
        assert_eq!(
            preferred_receive_dir(),
            Some(home.join("Downloads").join("LocalSend"))
        );
    }

    #[test]
    fn writable_dirs_are_created_and_probed() {
        let dir = std::env::temp_dir().join(format!(
            "localsend-fs-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or_default()
        ));
        let nested = dir.join("a").join("b");
        assert!(ensure_writable_dir(&nested));
        assert!(nested.is_dir());
        // The probe file must not be left behind.
        assert!(!nested.join(".localsend-write-test").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_receive_dir_falls_back_to_the_private_folder() {
        let dir = std::env::temp_dir().join(format!(
            "localsend-fs-resolve-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or_default()
        ));
        let writable = dir.join("writable");
        let candidates = vec![
            PathBuf::from("/proc/localsend-cannot-exist"),
            writable.clone(),
        ];
        assert_eq!(resolve_first_writable(&candidates), Some(writable));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_receive_dir_prefers_the_configured_folder() {
        let dir = std::env::temp_dir().join(format!(
            "localsend-fs-configured-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or_default()
        ));
        let configured = dir.join("chosen");
        let resolved = resolve_receive_dir(Some(&configured.to_string_lossy()));
        assert_eq!(resolved, configured);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn configured_folder_is_probed_before_the_download_folder() {
        let configured = PathBuf::from("/tmp/localsend-configured-order");
        let candidates = receive_candidates(Some(&configured.to_string_lossy()));
        assert_eq!(candidates.first(), Some(&configured));
        assert!(candidates.contains(&preferred_receive_dir().expect("HOME")));
        assert_eq!(candidates.last(), Some(&private_receive_dir()));
    }

    #[test]
    fn empty_configuration_starts_with_the_download_folder() {
        let candidates = receive_candidates(None);
        assert_eq!(candidates.first(), preferred_receive_dir().as_ref());
        assert_eq!(candidates.last(), Some(&private_receive_dir()));
    }
}
