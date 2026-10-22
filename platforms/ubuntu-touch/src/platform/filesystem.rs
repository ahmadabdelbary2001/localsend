// Confined filesystem access for Ubuntu Touch.
//
// Production packages use common AppArmor policy groups only. File access is
// limited to the click application's XDG directories. Received files are
// staged in app-private storage and offered to the user via Content Hub so the
// file manager can save them into shared storage. Other files are imported via
// Content Hub rather than by scanning the shared filesystem.

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

/// The preferred user-visible destination, `~/Downloads/LocalSend`.
///
/// This is a Content Hub destination hint; the confined app does not write to
/// this shared path directly.
pub fn preferred_receive_dir() -> Option<PathBuf> {

    dirs_home().map(|home| home.join("Downloads").join(RECEIVE_FOLDER_NAME))
}

/// Fallback when `~/Downloads` cannot be written: `<app data>/received`.
pub fn private_receive_dir() -> PathBuf {
    app_data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp/localsend-received"))
        .join("received")
}

/// Creates `dir` and verifies that it is writable under the active confinement.
/// Shared-storage destinations typically fail this probe and must be handled
/// through Content Hub.
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

/// Resolves where received files are written before Content Hub export.
///
/// Use a configured directory only when the app can actually write to it.
/// Otherwise stage the file in the app-private `received` directory; the QML
/// Content Hub exporter then hands it to the file manager for shared storage.
pub fn resolve_receive_dir(configured: Option<&str>) -> PathBuf {

    resolve_receive_dir_with(configured, Some(private_receive_dir()))
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
