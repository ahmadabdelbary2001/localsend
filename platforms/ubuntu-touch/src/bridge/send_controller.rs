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

#[derive(Clone, Debug)]
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
                fingerprint: d.fingerprint,
                host: d.ip,
                port: d.port,
                protocol,
                alias: d.alias,
            }
        } else if let Some(fav) = self.favorites.as_ref().and_then(|f| f.find(&fp)) {
            SendTarget {
                fingerprint: fav.fingerprint,
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
            fingerprint: Uuid::new_v4().to_string(),
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

        let paths: Vec<String> = match serde_json::from_str::<Value>(&json) {
            Ok(Value::Array(a)) => a
                .into_iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect(),
            _ => {
                self.error_message = QString::from("invalid paths JSON");
                self.state_changed();
                return;
            }
        };
        if paths.is_empty() {
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

        for p in &paths {
            let path = PathBuf::from(p);
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file")
                .to_string();

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

    pub fn collect_directory_files(&mut self, dir_path: QString) -> QString {
        let dir = PathBuf::from(dir_path.to_string());
        if !dir.is_dir() {
            return QString::from("[]");
        }
        let mut files = Vec::new();
        fn scan(dir: &std::path::Path, acc: &mut Vec<String>) {
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file() {
                        if let Some(s) = p.to_str() {
                            acc.push(s.to_string());
                        }
                    } else if p.is_dir() {
                        scan(&p, acc);
                    }
                }
            }
        }
        scan(&dir, &mut files);
        serde_json::to_string(&files).unwrap_or_else(|_| "[]".into()).into()
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

    pub fn list_installed_apps(&mut self) -> QString {
        #[derive(serde::Serialize)]
        struct AppItem {
            name: String,
            path: String,
            icon: String,
        }
        let mut apps = Vec::new();

        // 1. Scan Click packages in /opt/click.ubuntu.com
        let click_dir = PathBuf::from("/opt/click.ubuntu.com");
        if let Ok(entries) = std::fs::read_dir(&click_dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_dir() {
                    let pkg_name = p.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
                    if pkg_name.is_empty() || pkg_name.starts_with('.') {
                        continue;
                    }
                    if let Ok(sub_entries) = std::fs::read_dir(&p) {
                        for sub in sub_entries.flatten() {
                            let manifest = sub.path().join("manifest.json");
                            if manifest.is_file() {
                                if let Ok(data) = std::fs::read_to_string(&manifest) {
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&data) {
                                        let title = json.get("title").and_then(|v| v.as_str()).unwrap_or(&pkg_name);
                                        let icon = json.get("icon").and_then(|v| v.as_str()).unwrap_or("package");
                                        let path = sub.path().to_string_lossy().to_string();
                                        apps.push(AppItem {
                                            name: title.to_string(),
                                            path,
                                            icon: icon.to_string(),
                                        });
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }

        // 2. Scan desktop files in /usr/share/applications and ~/.local/share/applications
        let home = std::env::var("HOME").map(PathBuf::from).ok();
        let desktop_dirs = [
            PathBuf::from("/usr/share/applications"),
            home.as_ref().map(|h| h.join(".local/share/applications")).unwrap_or_default(),
        ];
        for ddir in &desktop_dirs {
            if let Ok(entries) = std::fs::read_dir(ddir) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.extension().map_or(false, |ext| ext == "desktop") {
                        if let Ok(content) = std::fs::read_to_string(&p) {
                            let mut name = None;
                            let mut icon = None;
                            let mut no_display = false;
                            for line in content.lines() {
                                if line.starts_with("Name=") && name.is_none() {
                                    name = Some(line["Name=".len()..].trim().to_string());
                                } else if line.starts_with("Icon=") && icon.is_none() {
                                    icon = Some(line["Icon=".len()..].trim().to_string());
                                } else if line.starts_with("NoDisplay=true") {
                                    no_display = true;
                                }
                            }
                            if !no_display {
                                if let Some(n) = name {
                                    if !n.is_empty() {
                                        apps.push(AppItem {
                                            name: n,
                                            path: p.to_string_lossy().to_string(),
                                            icon: icon.unwrap_or_else(|| "software-properties".into()),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Scan ~/Downloads for any .click or .deb packages
        if let Some(h) = &home {
            let downloads = h.join("Downloads");
            if let Ok(entries) = std::fs::read_dir(&downloads) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if let Some(ext) = p.extension() {
                        if ext == "click" || ext == "deb" {
                            let fname = p.file_name().and_then(|n| n.to_str()).unwrap_or("package").to_string();
                            apps.push(AppItem {
                                name: format!("{fname} (installer)"),
                                path: p.to_string_lossy().to_string(),
                                icon: "package".to_string(),
                            });
                        }
                    }
                }
            }
        }

        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        apps.dedup_by(|a, b| a.name == b.name);

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
