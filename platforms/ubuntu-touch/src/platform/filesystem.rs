// SPDX-License-Identifier: Apache-2.0
//
// Confined filesystem access for Ubuntu Touch.
//
// A click package may only write into its own XDG folders (`~/.config`,
// `~/.cache`, `~/.local/share` beneath the click package name) unless the
// AppArmor hook grants more. The hook therefore declares
//
//     write_path: /home/phablet/Downloads/
//     read_path:  /home/phablet/Documents/
//
// which is what lets received files land in the user visible
// `~/Downloads/LocalSend` folder and lets the app picker list packages stored
// in `~/Documents` (`write_path` already grants read access to Downloads).
//
// Both fields are click-review redflags, so the OpenStore does not accept the
// upload automatically and asks for a manual review; a manual `click install`
// does accept them. Every folder is therefore probed before it is used and the
// app falls back to its own data folder when a grant is missing, so a build
// without the hook still works.

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

/// The user visible receive folder, `~/Downloads/LocalSend`.
///
/// The AppArmor hook grants write access to `~/Downloads`, so this is the
/// folder received files are written into (see `resolve_receive_dir`).
pub fn preferred_receive_dir() -> Option<PathBuf> {
    dirs_home().map(|home| home.join("Downloads").join(RECEIVE_FOLDER_NAME))
}

/// Fallback when `~/Downloads` cannot be written: `<app data>/received`.
pub fn private_receive_dir() -> PathBuf {
    app_data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp/localsend-received"))
        .join("received")
}

/// Creates `dir` (and its parents) and verifies that files can actually be
/// written into it.
///
/// `create_dir_all` alone is not enough: on Ubuntu Touch `~/Documents` exists
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

/// Resolves where received files are stored.
///
/// Order: the folder configured in the settings (when it is really writable),
/// then the default `~/Downloads/LocalSend` (writable thanks to the AppArmor
/// `write_path` grant) and finally the app-private `received` folder.
pub fn resolve_receive_dir(configured: Option<&str>) -> PathBuf {
    resolve_receive_dir_with(configured, preferred_receive_dir())
}

fn resolve_receive_dir_with(configured: Option<&str>, default: Option<PathBuf>) -> PathBuf {
    if let Some(dir) = configured.map(str::trim).filter(|d| !d.is_empty()) {
        let configured = PathBuf::from(dir);
        if ensure_writable_dir(&configured) {
            log::debug!("receiving into {}", configured.display());
            return configured;
        }
        log::warn!(
            "configured receive folder {} is not writable, using the default",
            configured.display()
        );
    }

    if let Some(default) = default {
        if ensure_writable_dir(&default) {
            log::debug!("receiving into {}", default.display());
            return default;
        }
        log::warn!(
            "{} is not writable, falling back to the app folder",
            default.display()
        );
    }

    let private = private_receive_dir();
    if let Err(error) = std::fs::create_dir_all(&private) {
        log::error!("cannot create {}: {error}", private.display());
    }
    log::debug!("receiving into {}", private.display());
    private
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "localsend-fs-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or_default()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

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
        // HOME is always set on the device and on the CI runner; a developer
        // machine without it simply skips the check.
        let Some(home) = dirs_home() else { return };
        assert_eq!(
            preferred_receive_dir(),
            Some(home.join("Downloads").join("LocalSend"))
        );
    }

    #[test]
    fn writable_dirs_are_created_and_probed() {
        let dir = temp_dir("writable");
        let nested = dir.join("a").join("b");
        assert!(ensure_writable_dir(&nested));
        assert!(nested.is_dir());
        // The probe file must not be left behind.
        assert!(!nested.join(".localsend-write-test").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_receive_dir_uses_the_default_folder() {
        let root = temp_dir("default");
        let default = root.join("Downloads").join("LocalSend");
        assert_eq!(
            resolve_receive_dir_with(None, Some(default.clone())),
            default,
            "received files belong in the user visible folder"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn resolve_receive_dir_prefers_the_configured_folder() {
        let root = temp_dir("configured");
        let default = root.join("Downloads").join("LocalSend");
        let configured = root.join("chosen");
        assert_eq!(
            resolve_receive_dir_with(Some(&configured.to_string_lossy()), Some(default)),
            configured
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(unix)]
    fn resolve_receive_dir_ignores_an_unwritable_configured_folder() {
        // `/proc` never accepts new files, so the probe has to reject it.
        let root = temp_dir("unwritable");
        let default = root.join("Downloads").join("LocalSend");
        assert_eq!(
            resolve_receive_dir_with(Some("/proc/localsend-cannot-exist"), Some(default.clone())),
            default
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(unix)]
    fn resolve_receive_dir_falls_back_to_the_app_folder() {
        let resolved = resolve_receive_dir_with(
            Some("/proc/localsend-cannot-exist"),
            Some(PathBuf::from("/proc/localsend-cannot-exist-either")),
        );
        assert_eq!(resolved, private_receive_dir());
    }
}
