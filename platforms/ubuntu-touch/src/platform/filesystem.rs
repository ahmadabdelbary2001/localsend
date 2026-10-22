// SPDX-License-Identifier: Apache-2.0
//
// Confined filesystem access for Ubuntu Touch.
// Click confinement grants private writable XDG directories beneath the
// click package name declared in manifest.json. Everything else is read-only:
// granting writes elsewhere needs `read_path` / `write_path` in the AppArmor
// hook, and those are click-review redflags that make the OpenStore reject the
// upload (HTTP 400). Received files are therefore written into the app data
// folder and exported to the user visible `~/Downloads/LocalSend` folder
// through the content hub (see qml/components/ReceiveExporter.qml).

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

/// The user visible folder received files are exported to,
/// `~/Downloads/LocalSend`.
///
/// The app itself cannot write there (that would need `write_path`, an
/// AppArmor redflag the OpenStore refuses), so this is only the target of the
/// content hub export in `ReceiveExporter`: the file manager writes the file
/// on the app's behalf.
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

/// Resolves where received files are stored.
///
/// A confined click package may only write into its own standard folders, so
/// the default is the app-private `received` folder. A configured folder is
/// used when the app can really write into it (the destination picker only
/// offers folders that pass that probe).
///
/// Files are made visible to the user by exporting them to
/// `~/Downloads/LocalSend` through the content hub (`ReceiveExporter`).
/// Writing there directly would need `write_path` in the AppArmor hook, which
/// is a click-review redflag and makes the OpenStore reject the upload.
pub fn resolve_receive_dir(configured: Option<&str>) -> PathBuf {
    if let Some(dir) = configured.map(str::trim).filter(|d| !d.is_empty()) {
        let configured = PathBuf::from(dir);
        if ensure_writable_dir(&configured) {
            log::debug!("receiving into {}", configured.display());
            return configured;
        }
        log::warn!(
            "configured receive folder {} is not writable, falling back",
            configured.display()
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
    fn resolve_receive_dir_uses_the_private_folder_by_default() {
        assert_eq!(
            resolve_receive_dir(None),
            private_receive_dir(),
            "received files must go to the one folder the click may write"
        );
        assert!(private_receive_dir().is_dir());
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
    #[cfg(unix)]
    fn resolve_receive_dir_ignores_an_unwritable_configured_folder() {
        // `/proc` never accepts new files, so the probe has to reject it.
        let resolved = resolve_receive_dir(Some("/proc/localsend-cannot-exist"));
        assert_eq!(resolved, private_receive_dir());
    }
}
