// SPDX-License-Identifier: Apache-2.0
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};

use qmetaobject::prelude::*;
use serde_json::Value;
use uuid::Uuid;

use localsend::model::discovery::ProtocolType;

use crate::application::discovery_service::DiscoveryServiceHandle;
use crate::application::favorites_service::FavoritesService;
use crate::application::identity_service::DeviceIdentity;
use crate::application::settings_service::SettingsService;
use crate::application::send_service::{
    SendCommand, SendEvent, SendFileEntry, SendServiceHandle, SendTarget,
};
use crate::platform::packages::{self, PackageFile};

#[derive(Clone, Debug, PartialEq)]
pub struct OutgoingEntry {
    pub file_id: String,
    pub name: String,
    pub size: u64,
    pub progress: f64,
    pub status: String, // "queue" | "sending" | "finished" | "failed"
    pub error: Option<String>,
}

/// How long a full package scan result is reused before the storage is
/// searched again.
const APP_SCAN_MAX_AGE_SECS: u64 = 300;
/// How long to wait before retrying a scan that found nothing. Without this a
/// device without packages would restart the scan on every QML poll.
const APP_SCAN_RETRY_SECS: u64 = 20;

/// State of the background package scan.
#[derive(Default)]
struct AppScanState {
    running: bool,
    /// Time of the last finished (full) scan, seconds since the epoch.
    last_scan: u64,
    /// Time the last scan was started, seconds since the epoch.
    last_attempt: u64,
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[derive(QObject)]
pub struct SendController {
    base: qt_base_class!(trait QObject),

    active: qt_property!(bool; NOTIFY state_changed),
    done: qt_property!(bool; NOTIFY state_changed),
    target_alias: qt_property!(QString; NOTIFY state_changed),
    total_count: qt_property!(i32; NOTIFY state_changed),
    finished_count: qt_property!(i32; NOTIFY state_changed),
    failed_count: qt_property!(i32; NOTIFY state_changed),
    error_message: qt_property!(QString; NOTIFY state_changed),
    status: qt_property!(QString; NOTIFY state_changed),
    pin_invalid: qt_property!(bool; NOTIFY state_changed),
    /// True while the background package scan is running, so the app picker
    /// can show a progress indicator instead of "no apps found".
    app_scan_running: qt_property!(bool; NOTIFY app_scan_changed),

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),
    files_changed: qt_signal!(),
    /// Emitted when the cached package list changed (after the priority phase
    /// and after the full scan), so the app picker can show the results.
    app_packages_changed: qt_signal!(),
    /// Emitted when the running state of the package scan changes.
    app_scan_changed: qt_signal!(),

    /// paths_json = JSON array of absolute file paths.
    send_files: qt_method!(fn(&mut self, fingerprint: QString, paths_json: QString)),
    send_to_address: qt_method!(
        fn(
            &mut self,
            ip: QString,
            port: u32,
            https: bool,
            alias: QString,
            paths_json: QString,
        )
    ),
    create_text_file: qt_method!(fn(&mut self, text: QString) -> QString),
    /// Copies Content Hub-imported files into persistent app-private storage.
    stage_imported_files: qt_method!(fn(&mut self, paths_json: QString) -> QString),
    collect_directory_files: qt_method!(fn(&mut self, dir_path: QString) -> QString),
    list_directory: qt_method!(fn(&mut self, dir_path: QString) -> QString),
    /// `kind` is "click" (default) or "apk".
    /// Lists package files (.click / .apk) that can be shared.
    ///
    /// `kind` selects the package format: `"click"` (Ubuntu Touch), `"apk"`
    /// (Android) or `"all"`. `query` filters by name or path.
    list_app_packages: qt_method!(fn(&mut self, kind: QString, query: QString) -> QString),
    /// Forces a fresh package scan (the picker's refresh button).
    refresh_app_packages: qt_method!(fn(&mut self)),
    selection_info: qt_method!(fn(&mut self, paths_json: QString) -> QString),
    /// Per-file details for the selection list (name / size / image / ext).
    selection_items: qt_method!(fn(&mut self, paths_json: QString) -> QString),
    home_directory: qt_method!(fn(&self) -> QString),
    /// True when `path` exists and is a directory.
    directory_exists: qt_method!(fn(&self, path: QString) -> bool),
    /// True only for readable regular files inside LocalSend app-private data.
    can_read_file: qt_method!(fn(&self, path: QString) -> bool),
    /// True only if the directory can be read inside app-private storage.
    can_read_directory: qt_method!(fn(&self, path: QString) -> bool),
    /// Creates a single folder (no parents). Returns the path or "" on error.
    create_directory: qt_method!(fn(&mut self, path: QString) -> QString),
    submit_pin: qt_method!(fn(&mut self, pin: QString)),
    cancel: qt_method!(fn(&mut self)),
    dismiss: qt_method!(fn(&mut self)),
    poll: qt_method!(fn(&mut self)),

    handle: Option<Arc<SendServiceHandle>>,
    discovery: Option<Arc<DiscoveryServiceHandle>>,
    favorites: Option<Arc<FavoritesService>>,
    identity: Arc<DeviceIdentity>,
    session_id: Option<String>,
    settings: Arc<SettingsService>,
    entries: Arc<RwLock<Vec<OutgoingEntry>>>,

    /// Package files found on the device (see platform::packages).
    app_packages: Arc<RwLock<Vec<PackageFile>>>,
    /// State of the background scan: running flag and time of the last scan.
    app_scan: Arc<Mutex<AppScanState>>,
    /// Set by the scan thread when the cached packages changed; poll() turns
    /// it into the `app_packages_changed` signal.
    app_scan_dirty: Arc<AtomicBool>,
}

impl SendController {
    pub fn new(
        identity: Arc<DeviceIdentity>,
        discovery: Arc<DiscoveryServiceHandle>,
        entries: Arc<RwLock<Vec<OutgoingEntry>>>,
        settings: Arc<SettingsService>,
        favorites: Arc<FavoritesService>,
    ) -> Self {
        let handle = SendServiceHandle::spawn(identity.clone());
        let mut controller = Self {
            base: Default::default(),
            active: false,
            done: false,
            target_alias: QString::default(),
            total_count: 0,
            finished_count: 0,
            failed_count: 0,
            error_message: QString::default(),
            status: QString::default(),
            pin_invalid: false,
            app_scan_running: false,
            state_changed: Default::default(),
            log_message: Default::default(),
            files_changed: Default::default(),
            app_packages_changed: Default::default(),
            app_scan_changed: Default::default(),
            send_files: Default::default(),
            send_to_address: Default::default(),
            create_text_file: Default::default(),
            stage_imported_files: Default::default(),
            collect_directory_files: Default::default(),
            list_directory: Default::default(),
            list_app_packages: Default::default(),
            refresh_app_packages: Default::default(),
            selection_info: Default::default(),
            selection_items: Default::default(),
            home_directory: Default::default(),
            directory_exists: Default::default(),
            can_read_file: Default::default(),
            can_read_directory: Default::default(),
            create_directory: Default::default(),
            submit_pin: Default::default(),
            cancel: Default::default(),
            dismiss: Default::default(),
            poll: Default::default(),
            handle: Some(Arc::new(handle)),
            discovery: Some(discovery),
            favorites: Some(favorites),
            identity,
            session_id: None,
            entries,
            settings,
            app_packages: Arc::new(RwLock::new(Vec::new())),
            app_scan: Arc::new(Mutex::new(AppScanState::default())),
            app_scan_dirty: Arc::new(AtomicBool::new(false)),
        };
        // Scan at startup: the picker then has results the moment it is
        // opened instead of showing an empty list for a few seconds.
        controller.ensure_app_scan(false);
        controller
    }

    pub fn send_files(&mut self, fingerprint: QString, paths_json: QString) {
        let fp = fingerprint.to_string();

        let target = if let Some(d) = self
            .discovery
            .as_ref()
            .and_then(|dh| dh.snapshot().iter().find(|d| d.fingerprint == fp).cloned())
        {
            let protocol = if d.https {
                ProtocolType::Https
            } else {
                ProtocolType::Http
            };
            SendTarget {
                expected_fingerprint: Some(d.fingerprint),
                host: d.ip,
                port: d.port,
                protocol,
                alias: d.alias,
            }
        } else if let Some(fav) = self.favorites.as_ref().and_then(|f| f.find(&fp)) {
            SendTarget {
                expected_fingerprint: Some(fav.fingerprint),
                host: fav.ip,
                port: fav.port,
                protocol: ProtocolType::Https,
                alias: fav.alias,
            }
        } else {
            self.error_message = QString::from(format!("device not found: {fp}"));
            self.state_changed();
            return;
        };

        self.dispatch_send(target, paths_json);
    }

    pub fn send_to_address(
        &mut self,
        ip: QString,
        port: u32,
        https: bool,
        alias: QString,
        paths_json: QString,
    ) {
        let host = ip.to_string().trim().to_string();
        if host.is_empty() {
            self.error_message = QString::from("IP address cannot be empty");
            self.state_changed();
            return;
        }
        let alias_str = alias.to_string();
        let target = SendTarget {
            // Unknown certificate for a manual address: do not pin.
            expected_fingerprint: None,
            host: host.clone(),
            port: port.min(u16::MAX as u32) as u16,
            protocol: if https {
                ProtocolType::Https
            } else {
                ProtocolType::Http
            },
            alias: if alias_str.is_empty() { host } else { alias_str },
        };
        self.dispatch_send(target, paths_json);
    }

    fn dispatch_send(&mut self, target: SendTarget, paths_json: QString) {
        let json = paths_json.to_string();

        // Entries are either absolute path strings or objects
        // { "path": ..., "name": ... } (folder sends keep their relative name).
        let items: Vec<(PathBuf, Option<String>)> = match serde_json::from_str::<Value>(&json) {
            Ok(Value::Array(a)) => a
                .into_iter()
                .filter_map(|v| match v {
                    Value::String(path) => Some((PathBuf::from(path), None)),
                    Value::Object(map) => {
                        let path = map.get("path")?.as_str()?.to_string();
                        let name = map
                            .get("name")
                            .and_then(|n| n.as_str())
                            .map(str::to_string);
                        Some((PathBuf::from(path), name))
                    }
                    _ => None,
                })
                .collect(),
            _ => {
                self.error_message = QString::from("invalid paths JSON");
                self.state_changed();
                return;
            }
        };
        if items.is_empty() {
            return;
        }

        let session_id = Uuid::new_v4().to_string();
        self.session_id = Some(session_id.clone());
        self.target_alias = QString::from(target.alias.clone());
        self.active = true;
        self.done = false;
        self.error_message = QString::default();
        self.status = QString::from("sending");
        self.pin_invalid = false;

        let mut files: Vec<SendFileEntry> = Vec::new();
        let mut entries: Vec<OutgoingEntry> = Vec::new();
        let mut validation_errors: Vec<String> = Vec::new();

        for (path, custom_name) in &items {
            let path = path.clone();
            let name = custom_name.clone().unwrap_or_else(|| {
                path.file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("file")
                    .to_string()
            });

            // C03: explicit validation. A file that cannot be stat'ed or
            // opened must not silently become a 0-byte transfer.
            let metadata = match std::fs::metadata(&path) {
                Ok(m) => m,
                Err(e) => {
                    validation_errors.push(format!("{}: {e}", path.display()));
                    continue;
                }
            };
            if !metadata.is_file() {
                validation_errors.push(format!("{}: not a regular file", path.display()));
                continue;
            }
            if let Err(e) = std::fs::File::open(&path) {
                validation_errors.push(format!("{}: cannot open ({e})", path.display()));
                continue;
            }
            let size = metadata.len();

            let file_id = Uuid::new_v4().to_string();
            files.push(SendFileEntry {
                file_id: file_id.clone(),
                path: path.clone(),
                name: name.clone(),
                size,
            });
            entries.push(OutgoingEntry {
                file_id,
                name,
                size,
                progress: 0.0,
                status: "queue".into(),
                error: None,
            });
        }

        if !validation_errors.is_empty() {
            self.error_message = QString::from(format!(
                "Cannot send file(s): {}",
                validation_errors.join("; ")
            ));
            self.state_changed();
            return;
        }
        self.total_count = entries.len() as i32;
        self.finished_count = 0;
        self.failed_count = 0;

        if let Ok(mut g) = self.entries.write() {
            *g = entries;
        }

        let snap = self.settings.snapshot();

        if let Some(h) = &self.handle {
            h.send(SendCommand::Start {
                session_id: session_id.clone(),
                target,
                files,
                sender_alias: snap.alias.clone(),
                sender_port: snap.port,
                sender_https: snap.https,
                sender_fingerprint: self.identity.fingerprint.clone(),
                pin: None,
                create_checksums: snap.create_checksums,
            });
        }

        self.files_changed();
        self.state_changed();
        self.log_message(QString::from(format!(
            "Sending {} file(s) to {}",
            self.total_count, self.target_alias
        )));
    }

    fn create_text_file(&mut self, text: QString) -> QString {
        let content = text.to_string();
        if content.trim().is_empty() {
            return QString::default();
        }
        let Some(data_dir) = crate::platform::filesystem::app_data_dir() else {
            log::warn!("[send_controller] app data directory is unavailable for clipboard text");
            return QString::default();
        };
        let cache_dir = data_dir.join("outgoing_text");
        if let Err(e) = std::fs::create_dir_all(&cache_dir) {
            log::warn!("[send_controller] failed to create private text directory: {e}");
            return QString::default();
        }
        let file_path = cache_dir.join(format!("{}.txt", Uuid::new_v4()));
        if let Err(e) = std::fs::write(&file_path, content.as_bytes()) {
            log::warn!("[send_controller] failed to write text file: {e}");
            return QString::default();
        }
        QString::from(file_path.to_string_lossy().to_string())
    }

    /// Copies files delivered to the app through Content Hub into persistent
    /// app-private storage before the Content Hub transfer is finalized.
    pub fn stage_imported_files(&mut self, paths_json: QString) -> QString {
        fn rollback(paths: &[String]) {
            for path in paths {
                let _ = std::fs::remove_file(path);
            }
        }

        let raw = paths_json.to_string();
        let sources: Vec<String> = match serde_json::from_str(&raw) {
            Ok(paths) => paths,
            Err(error) => {
                log::warn!("[send_controller] invalid Content Hub paths: {error}");
                return QString::from("[]");
            }
        };
        if sources.is_empty() || sources.len() > 512 {
            log::warn!("[send_controller] rejecting an empty or oversized Content Hub import batch");
            return QString::from("[]");
        }

        let Some(data_dir) = crate::platform::filesystem::app_data_dir() else {
            log::warn!("[send_controller] app data directory is unavailable");
            return QString::from("[]");
        };
        let import_dir = data_dir.join("imports");
        if let Err(error) = std::fs::create_dir_all(&import_dir) {
            log::warn!("[send_controller] cannot create private import directory: {error}");
            return QString::from("[]");
        }

        let mut staged: Vec<String> = Vec::new();
        for source_text in sources {
            let source = PathBuf::from(source_text);
            let metadata = match std::fs::symlink_metadata(&source) {
                Ok(metadata) if source.is_absolute() && metadata.file_type().is_file() => metadata,
                Ok(_) => {
                    rollback(&staged);
                    return QString::from("[]");
                }
                Err(error) => {
                    log::debug!("[send_controller] imported item is not readable: {error}");
                    rollback(&staged);
                    return QString::from("[]");
                }
            };
            let _ = metadata;
            let Some(name) = source.file_name().and_then(|name| name.to_str()) else {
                rollback(&staged);
                return QString::from("[]");
            };
            if name.is_empty() || name == "." || name == ".." {
                rollback(&staged);
                return QString::from("[]");
            }

            let mut destination = import_dir.join(name);
            if destination.exists() {
                let stem = source.file_stem().and_then(|s| s.to_str()).filter(|s| !s.is_empty()).unwrap_or("imported");
                let ext = source.extension().and_then(|s| s.to_str()).filter(|s| !s.is_empty());
                let mut index = 1u32;
                loop {
                    let candidate_name = match ext {
                        Some(ext) => format!("{stem} ({index}).{ext}"),
                        None => format!("{stem} ({index})"),
                    };
                    destination = import_dir.join(candidate_name);
                    if !destination.exists() {
                        break;
                    }
                    if index >= 10_000 {
                        let unique = Uuid::new_v4();
                        destination = match ext {
                            Some(ext) => import_dir.join(format!("{stem}-{unique}.{ext}")),
                            None => import_dir.join(format!("{stem}-{unique}")),
                        };
                        break;
                    }
                    index += 1;
                }
            }

            match std::fs::copy(&source, &destination) {
                Ok(_) => staged.push(destination.to_string_lossy().to_string()),
                Err(error) => {
                    log::warn!("[send_controller] failed to stage imported file: {error}");
                    // std::fs::copy may leave a partial destination on failure.
                    let _ = std::fs::remove_file(&destination);
                    rollback(&staged);
                    return QString::from("[]");
                }
            }
        }

        QString::from(serde_json::to_string(&staged).unwrap_or_else(|_| "[]".to_string()))
    }

    /// Recursively collects files below `dir_path`. Every entry carries the
    /// relative name `<folder>/<relative path>` so the receiver keeps the
    /// directory structure, matching Flutter's AddDirectoryAction.
    pub fn collect_directory_files(&mut self, dir_path: QString) -> QString {
        #[derive(serde::Serialize)]
        struct FolderFile {
            path: String,
            name: String,
        }

        let dir = PathBuf::from(dir_path.to_string());
        if !crate::platform::filesystem::is_app_private_path(&dir) || !dir.is_dir() {
            log::debug!("[send_controller] refusing to scan a folder outside app-private storage");
            return QString::from("[]");
        }
        let folder_name = dir
            .file_name()
            .and_then(|s| s.to_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("folder")
            .to_string();

        let mut files: Vec<FolderFile> = Vec::new();
        fn scan(
            root: &std::path::Path,
            dir: &std::path::Path,
            folder_name: &str,
            acc: &mut Vec<FolderFile>,
        ) {
            let Ok(entries) = std::fs::read_dir(dir) else {
                return;
            };
            let mut entries: Vec<_> = entries.flatten().collect();
            entries.sort_by_key(|entry| entry.file_name());
            for entry in entries {
                let Ok(file_type) = entry.file_type() else { continue };
                if file_type.is_symlink() {
                    continue;
                }
                let path = entry.path();
                if file_type.is_file() {
                    let Some(full) = path.to_str() else { continue };
                    let relative = path
                        .strip_prefix(root)
                        .ok()
                        .map(|p| p.to_string_lossy().replace('\\', "/"))
                        .unwrap_or_else(|| {
                            path.file_name()
                                .map(|n| n.to_string_lossy().to_string())
                                .unwrap_or_default()
                        });
                    acc.push(FolderFile {
                        path: full.to_string(),
                        name: format!("{}/{}", folder_name, relative),
                    });
                } else if path.is_dir() {
                    scan(root, &path, folder_name, acc);
                }
            }
        }
        scan(&dir, &dir, &folder_name, &mut files);
        serde_json::to_string(&files).unwrap_or_else(|_| "[]".into()).into()
    }

    /// Summary for the selection card: number of files, total size and names.
    pub fn selection_info(&mut self, paths_json: QString) -> QString {
        let json = paths_json.to_string();
        let items: Vec<(PathBuf, Option<String>)> = match serde_json::from_str::<Value>(&json) {
            Ok(Value::Array(a)) => a
                .into_iter()
                .filter_map(|v| match v {
                    Value::String(path) => Some((PathBuf::from(path), None)),
                    Value::Object(map) => {
                        let path = map.get("path")?.as_str()?.to_string();
                        let name = map
                            .get("name")
                            .and_then(|n| n.as_str())
                            .map(str::to_string);
                        Some((PathBuf::from(path), name))
                    }
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };

        let mut size: u64 = 0;
        let mut names: Vec<String> = Vec::new();
        let mut missing: usize = 0;
        for (path, custom_name) in &items {
            match std::fs::metadata(path) {
                Ok(meta) => size = size.saturating_add(meta.len()),
                Err(_) => missing += 1,
            }
            names.push(custom_name.clone().unwrap_or_else(|| {
                path.file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("file")
                    .to_string()
            }));
        }

        let info = serde_json::json!({
            "count": items.len(),
            "size": size,
            "names": names,
            "missing": missing,
        });
        QString::from(info.to_string())
    }

    pub fn home_directory(&self) -> QString {
        QString::from(
            std::env::var("HOME").unwrap_or_else(|_| "/home/phablet".to_string()),
        )
    }

    pub fn can_read_directory(&self, path: QString) -> bool {
        let raw = path.to_string();
        let dir = PathBuf::from(raw.trim());
        !raw.trim().is_empty()
            && crate::platform::filesystem::is_app_private_path(&dir)
            && std::fs::read_dir(&dir).is_ok()
    }

    pub fn list_directory(&mut self, dir_path: QString) -> QString {
        #[derive(serde::Serialize)]
        struct DirEntry {
            name: String,
            path: String,
            is_dir: bool,
            size: u64,
        }
        let p_str = dir_path.to_string();
        let target_dir = if p_str.trim().is_empty() {
            std::env::var("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/home/phablet"))
        } else {
            PathBuf::from(p_str)
        };

        if !crate::platform::filesystem::is_app_private_path(&target_dir) {
            log::debug!("[send_controller] refusing directory listing outside app-private storage");
            return QString::from("[]");
        }

        let mut entries_list = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&target_dir) {
            for entry in entries.flatten() {
                let Ok(file_type) = entry.file_type() else { continue };
                if file_type.is_symlink() {
                    continue;
                }
                let p = entry.path();
                let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
                if name.starts_with('.') {
                    continue; // Skip hidden files
                }
                let is_dir = p.is_dir();
                let size = if is_dir { 0 } else { p.metadata().map(|m| m.len()).unwrap_or(0) };
                entries_list.push(DirEntry {
                    name,
                    path: p.to_string_lossy().to_string(),
                    is_dir,
                    size,
                });
            }
        }
        entries_list.sort_by(|a, b| {
            b.is_dir.cmp(&a.is_dir).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });

        serde_json::to_string(&entries_list).unwrap_or_else(|_| "[]".into()).into()
    }

    /// Lists package files (.click / .apk) that can be shared with a peer.
    ///
    /// Unlike Flutter's Android APK picker, Ubuntu Touch has no installed-app
    /// archive to share, so the package *files* stored on the device are
    /// listed. They can live anywhere (download folder, home directory, SD
    /// card), so the whole storage is searched.
    ///
    /// The search runs in a background thread that is started when the
    /// controller is created: the first call usually returns the cached
    /// packages, later calls return the results of a newer scan. QML polls
    /// while the picker is open and reads `app_scan_running` to show a
    /// progress indicator.
    ///
    /// `kind` selects the package format: `"click"` (Ubuntu Touch), `"apk"`
    /// (Android) or `"all"`. `query` filters by name or path.
    pub fn list_app_packages(&mut self, kind: QString, query: QString) -> QString {
        self.ensure_app_scan(false);

        let kind = kind.to_string();
        let query = query.to_string();

        let packages = self
            .app_packages
            .read()
            .map(|p| p.clone())
            .unwrap_or_default();
        let matching = packages::filter(&packages, &kind, &query);

        let apps: Vec<serde_json::Value> = matching
            .iter()
            .map(|p| {
                serde_json::json!({
                    "name": p.name,
                    "path": p.path,
                    // Folder the package is stored in, shown below the name.
                    "folder": Path::new(&p.path)
                        .parent()
                        .map(|d| d.to_string_lossy().to_string())
                        .unwrap_or_default(),
                    "size": p.size,
                    "modified": p.modified,
                    "kind": p.kind(),
                    // Both formats render with the package icon:
                    // "stock_application" is not part of the Ubuntu Touch icon
                    // theme and falls back to a random glyph there.
                    "icon": "package-x-generic-symbolic",
                })
            })
            .collect();

        serde_json::to_string(&apps).unwrap_or_else(|_| "[]".into()).into()
    }

    /// Forces a new package scan (the refresh button of the app picker).
    pub fn refresh_app_packages(&mut self) {
        self.ensure_app_scan(true);
    }

    /// Starts the package scan when it is not running and the cache is stale.
    ///
    /// `force` ignores the cache age, but still never starts a second scan
    /// while one is running.
    fn ensure_app_scan(&mut self, force: bool) {
        let now = now_secs();

        let should_start = {
            let mut state = match self.app_scan.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            if state.running {
                false
            } else {
                let empty = self
                    .app_packages
                    .read()
                    .map(|p| p.is_empty())
                    .unwrap_or(true);
                let stale = now.saturating_sub(state.last_scan) > APP_SCAN_MAX_AGE_SECS;
                // Before the first scan completes, a failed attempt may be
                // retried after a delay. A completed empty result waits for
                // the normal cache age instead of rescanning on every poll.
                let retry_due = now.saturating_sub(state.last_attempt) >= APP_SCAN_RETRY_SECS;
                let start = force
                    || if empty && state.last_scan == 0 {
                        retry_due
                    } else {
                        stale
                    };
                if start {
                    state.running = true;
                    state.last_attempt = now;
                }
                start
            }
        };

        if !should_start {
            return;
        }

        if !self.app_scan_running {
            self.app_scan_running = true;
            self.app_scan_changed();
        }

        let packages = self.app_packages.clone();
        let scan_state = self.app_scan.clone();
        let scan_dirty = self.app_scan_dirty.clone();
        std::thread::spawn(move || {
            // Two phases: the folders the app may read (the LocalSend receive
            // folder, Downloads, Documents) are published one by one so the
            // picker fills up immediately. The broad roots (the whole home
            // folder, click caches) are walked afterwards and only replace the
            // list once they are done.
            let roots = packages::search_roots();
            let mut session = packages::ScanSession::new();

            for root in roots.iter().filter(|root| root.priority) {
                session.scan(std::slice::from_ref(root), packages::PRIORITY_BUDGET);
                let partial = session.packages();
                log::info!(
                    "package scan: {} package(s) after {}",
                    partial.len(),
                    root.path.display()
                );
                publish_packages(&packages, partial, &scan_dirty);
            }

            let broad: Vec<packages::SearchRoot> = roots
                .iter()
                .filter(|root| !root.priority)
                .cloned()
                .collect();
            session.scan(&broad, packages::BROAD_BUDGET);
            let found = session.into_packages();
            log::info!("package scan found {} package(s)", found.len());
            publish_packages(&packages, found, &scan_dirty);

            let mut state = match scan_state.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            state.running = false;
            state.last_scan = now_secs();
            drop(state);
            scan_dirty.store(true, Ordering::Relaxed);
        });
    }

    /// Checks that a source file exists, is not a symlink, is readable, and
    /// belongs to LocalSend's private data tree before exposing it to Content Hub.
    pub fn can_read_file(&self, path: QString) -> bool {
        let value = path.to_string();
        let candidate = Path::new(value.trim());
        if !crate::platform::filesystem::is_app_private_path(candidate) {
            return false;
        }
        let Ok(metadata) = std::fs::symlink_metadata(candidate) else {
            return false;
        };
        if !metadata.file_type().is_file() {
            return false;
        }
        std::fs::File::open(candidate).is_ok()
    }

    pub fn directory_exists(&self, path: QString) -> bool {
        let p = path.to_string();
        !p.trim().is_empty()
            && crate::platform::filesystem::is_app_private_path(Path::new(&p))
            && Path::new(&p).is_dir()
    }

    pub fn create_directory(&mut self, path: QString) -> QString {
        let p = path.to_string();
        if p.trim().is_empty() {
            return QString::default();
        }
        let target = Path::new(&p);
        if !crate::platform::filesystem::is_app_private_child_path(target) {
            log::debug!("[send_controller] refusing to create a folder outside app-private storage");
            return QString::default();
        }
        match std::fs::create_dir(&p) {
            Ok(()) => QString::from(p),
            // An existing folder is fine: the caller just navigates into it.
            Err(_) if Path::new(&p).is_dir() => QString::from(p),
            Err(error) => {
                log::warn!("cannot create {p}: {error}");
                QString::default()
            }
        }
    }

    /// Per-file details used by the send list: one row per selected path.
    pub fn selection_items(&mut self, paths_json: QString) -> QString {
        #[derive(serde::Serialize)]
        struct Item {
            path: String,
            name: String,
            size: u64,
            is_image: bool,
            ext: String,
        }

        const IMAGE_EXTENSIONS: &[&str] = &[
            "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "heic", "heif", "tif", "tiff",
            "avif",
        ];

        let json = paths_json.to_string();
        let items: Vec<(PathBuf, Option<String>)> = match serde_json::from_str::<Value>(&json) {
            Ok(Value::Array(a)) => a
                .into_iter()
                .filter_map(|v| match v {
                    Value::String(path) => Some((PathBuf::from(path), None)),
                    Value::Object(map) => {
                        let path = map.get("path")?.as_str()?.to_string();
                        let name = map
                            .get("name")
                            .and_then(|n| n.as_str())
                            .map(str::to_string);
                        Some((PathBuf::from(path), name))
                    }
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };

        let list: Vec<Item> = items
            .into_iter()
            .map(|(path, custom_name)| {
                let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
                let name = custom_name.unwrap_or_else(|| {
                    path.file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("file")
                        .to_string()
                });
                let ext = path
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                let is_image = IMAGE_EXTENSIONS.contains(&ext.as_str());
                Item {
                    path: path.to_string_lossy().to_string(),
                    name,
                    size,
                    is_image,
                    ext: ext.to_ascii_uppercase(),
                }
            })
            .collect();

        serde_json::to_string(&list).unwrap_or_else(|_| "[]".into()).into()
    }

    fn cancel(&mut self) {
        if let (Some(h), Some(sid)) = (&self.handle, &self.session_id) {
            h.send(SendCommand::Cancel {
                session_id: sid.clone(),
            });
        }
        self.done = true;
        self.active = false;
        self.status = QString::from("cancelled");
        self.state_changed();
    }

    fn submit_pin(&mut self, pin: QString) {
        if let (Some(h), Some(sid)) = (&self.handle, &self.session_id) {
            h.send(SendCommand::SubmitPin {
                session_id: sid.clone(),
                pin: pin.to_string(),
            });
        }
    }

    fn dismiss(&mut self) {
        self.session_id = None;
        self.active = false;
        self.done = false;
        self.status = QString::default();
        if let Ok(mut g) = self.entries.write() {
            g.clear();
        }
        self.files_changed();
        self.state_changed();
    }

    pub fn poll(&mut self) {
        // The package scan runs in a background thread; tell QML when the
        // cached results changed and when the scan finished, so the app picker
        // can show them (and stop its progress indicator).
        if self.app_scan_dirty.swap(false, Ordering::Relaxed) {
            self.app_packages_changed();
        }
        let running = match self.app_scan.lock() {
            Ok(state) => state.running,
            Err(poisoned) => poisoned.into_inner().running,
        };
        if running != self.app_scan_running {
            self.app_scan_running = running;
            self.app_scan_changed();
        }

        let events: Vec<SendEvent> = {
            let Some(h) = &self.handle else { return };
            let mut out = Vec::new();
            while let Some(e) = h.try_recv_event() {
                out.push(e);
            }
            out
        };

        for evt in events {
            match evt {
                SendEvent::Prepared { accepted, .. } => {
                    log::info!("[send] session prepared, {} accepted", accepted.len());
                }
                SendEvent::FileStarted { file_id, .. } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.status = "sending".into();
                        }
                    }
                    self.files_changed();
                }
                SendEvent::FileProgress {
                    file_id, progress, ..
                } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.progress = progress;
                        }
                    }
                    self.files_changed();
                }
                SendEvent::FileDone { file_id, .. } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.progress = 1.0;
                            e.status = "finished".into();
                        }
                    }
                    self.finished_count += 1;
                    self.files_changed();
                    self.state_changed();
                }
                SendEvent::FileFailed { file_id, error, .. } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.status = "failed".into();
                            e.error = Some(error.clone());
                        }
                    }
                    self.failed_count += 1;
                    self.files_changed();
                    self.state_changed();
                }
                SendEvent::PinRequired { invalid_pin, .. } => {
                    self.status = QString::from("pinRequired");
                    self.pin_invalid = invalid_pin;
                    self.state_changed();
                }
                SendEvent::Declined { .. } => {
                    self.status = QString::from("declined");
                    self.active = false;
                    self.done = true;
                    self.state_changed();
                }
                SendEvent::RecipientBusy { .. } => {
                    self.status = QString::from("recipientBusy");
                    self.active = false;
                    self.done = true;
                    self.state_changed();
                }
                SendEvent::TooManyAttempts { .. } => {
                    self.status = QString::from("tooManyAttempts");
                    self.active = false;
                    self.done = true;
                    self.state_changed();
                }
                SendEvent::Finished { ok, error, .. } => {
                    self.active = false;
                    self.done = true;
                    if ok {
                        self.status = QString::from("finished");
                    } else {
                        self.status = QString::from("finishedWithErrors");
                        self.error_message = QString::from(error.unwrap_or_default());
                    }
                    self.state_changed();
                }
                SendEvent::Log(msg) => {
                    log::info!("[send] {}", msg);
                    self.log_message(QString::from(msg));
                }
            }
        }
    }
}

/// Replaces the cached package list and marks it as changed for `poll()`.
fn publish_packages(
    cache: &Arc<RwLock<Vec<PackageFile>>>,
    found: Vec<PackageFile>,
    dirty: &AtomicBool,
) {
    if let Ok(mut guard) = cache.write() {
        *guard = found;
    }
    dirty.store(true, Ordering::Relaxed);
}
