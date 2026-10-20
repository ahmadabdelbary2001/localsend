// SPDX-License-Identifier: Apache-2.0
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

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

#[derive(Clone, Debug, PartialEq)]
pub struct OutgoingEntry {
    pub file_id: String,
    pub name: String,
    pub size: u64,
    pub progress: f64,
    pub status: String, // "queue" | "sending" | "finished" | "failed"
    pub error: Option<String>,
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

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),
    files_changed: qt_signal!(),

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
    collect_directory_files: qt_method!(fn(&mut self, dir_path: QString) -> QString),
    list_directory: qt_method!(fn(&mut self, dir_path: QString) -> QString),
    list_installed_apps: qt_method!(fn(&mut self) -> QString),
    selection_info: qt_method!(fn(&mut self, paths_json: QString) -> QString),
    home_directory: qt_method!(fn(&self) -> QString),
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
        Self {
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
            state_changed: Default::default(),
            log_message: Default::default(),
            files_changed: Default::default(),
            send_files: Default::default(),
            send_to_address: Default::default(),
            create_text_file: Default::default(),
            collect_directory_files: Default::default(),
            list_directory: Default::default(),
            list_installed_apps: Default::default(),
            selection_info: Default::default(),
            home_directory: Default::default(),
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
        }
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
        let cache_dir = std::env::temp_dir().join("localsend_text");
        if let Err(e) = std::fs::create_dir_all(&cache_dir) {
            log::warn!("[send_controller] failed to create text cache dir: {e}");
            return QString::default();
        }
        let file_path = cache_dir.join(format!("{}.txt", Uuid::new_v4()));
        if let Err(e) = std::fs::write(&file_path, content.as_bytes()) {
            log::warn!("[send_controller] failed to write text file: {e}");
            return QString::default();
        }
        QString::from(file_path.to_string_lossy().to_string())
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
        if !dir.is_dir() {
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
                let path = entry.path();
                if path.is_file() {
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

        let mut entries_list = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&target_dir) {
            for entry in entries.flatten() {
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

    /// Lists sendable package files (click/deb/apk/snap/appimage) found in
    /// the usual user folders. Unlike Flutter's Android APK picker, Ubuntu
    /// Touch has no installed-app archive to share, so only files are listed.
    pub fn list_installed_apps(&mut self) -> QString {
        #[derive(serde::Serialize)]
        struct AppItem {
            name: String,
            path: String,
            icon: String,
        }

        const EXTENSIONS: &[&str] = &[
            "click", "deb", "apk", "snap", "appimage", "flatpakref", "flatpak", "run",
        ];

        let home = std::env::var_os("HOME").map(PathBuf::from);
        let mut roots: Vec<PathBuf> = Vec::new();
        if let Some(home) = &home {
            for sub in ["Downloads", "Documents", "Desktop"] {
                roots.push(home.join(sub));
            }
            roots.push(home.clone());
        }
        for system in ["/opt/click.ubuntu.com", "/var/cache/click"] {
            roots.push(PathBuf::from(system));
        }

        let mut apps: Vec<AppItem> = Vec::new();
        for root in &roots {
            let Ok(entries) = std::fs::read_dir(root) else {
                continue;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_file() {
                    continue;
                }
                let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
                    continue;
                };
                if !EXTENSIONS.iter().any(|known| known.eq_ignore_ascii_case(ext)) {
                    continue;
                }
                let name = path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("package")
                    .to_string();
                let icon = match ext.to_ascii_lowercase().as_str() {
                    "apk" => "package-x-generic-symbolic",
                    "deb" | "click" | "snap" | "appimage" | "flatpakref" | "flatpak" | "run" => {
                        "stock_application"
                    }
                    _ => "stock_application",
                };
                apps.push(AppItem {
                    name,
                    path: path.to_string_lossy().to_string(),
                    icon: icon.to_string(),
                });
            }
        }

        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        apps.dedup_by(|a, b| a.path == b.path);

        serde_json::to_string(&apps).unwrap_or_else(|_| "[]".into()).into()
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
