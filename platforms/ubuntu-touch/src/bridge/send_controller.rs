// SPDX-License-Identifier: Apache-2.0
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use qmetaobject::prelude::*;
use serde_json::Value;
use uuid::Uuid;

use localsend::model::discovery::ProtocolType;

use crate::application::discovery_service::DiscoveryServiceHandle;
use crate::application::identity_service::DeviceIdentity;
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

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),
    files_changed: qt_signal!(),

    /// paths_json = JSON array of absolute file paths.
    send_files: qt_method!(fn(&mut self, fingerprint: QString, paths_json: QString)),
    cancel: qt_method!(fn(&mut self)),
    dismiss: qt_method!(fn(&mut self)),
    poll: qt_method!(fn(&mut self)),

    handle: Option<Arc<SendServiceHandle>>,
    discovery: Option<Arc<DiscoveryServiceHandle>>,
    identity: Arc<DeviceIdentity>,
    session_id: Option<String>,
    entries: Arc<RwLock<Vec<OutgoingEntry>>>,
}

impl SendController {
    pub fn new(
        identity: Arc<DeviceIdentity>,
        discovery: Arc<DiscoveryServiceHandle>,
        entries: Arc<RwLock<Vec<OutgoingEntry>>>,
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
            state_changed: Default::default(),
            log_message: Default::default(),
            files_changed: Default::default(),
            send_files: Default::default(),
            cancel: Default::default(),
            dismiss: Default::default(),
            poll: Default::default(),
            handle: Some(Arc::new(handle)),
            discovery: Some(discovery),
            identity,
            session_id: None,
            entries,
        }
    }

    pub fn send_files(&mut self, fingerprint: QString, paths_json: QString) {
        let fp = fingerprint.to_string();
        let json = paths_json.to_string();

        // Resolve target device from discovery snapshot.
        let Some(dh) = &self.discovery else { return };
        let Some(device) = dh.snapshot().iter().find(|d| d.fingerprint == fp).cloned() else {
            self.error_message = QString::from(format!("device not found: {fp}"));
            self.state_changed();
            return;
        };

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
        self.target_alias = QString::from(device.alias.clone());
        self.active = true;
        self.done = false;
        self.error_message = QString::default();

        let mut files: Vec<SendFileEntry> = Vec::new();
        let mut entries: Vec<OutgoingEntry> = Vec::new();
        for p in &paths {
            let path = PathBuf::from(p);
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file")
                .to_string();
            let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
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
        self.total_count = entries.len() as i32;
        self.finished_count = 0;
        self.failed_count = 0;

        if let Ok(mut g) = self.entries.write() {
            *g = entries;
        }

        let protocol = if device.https { ProtocolType::Https } else { ProtocolType::Http };
        let target = SendTarget {
            fingerprint: device.fingerprint.clone(),
            host: device.ip.clone(),
            port: device.port,
            protocol,
            alias: device.alias.clone(),
        };

        let sender_https = true; // TODO: read from settings
        let sender_port = 53317; // TODO: read from settings

        if let Some(h) = &self.handle {
            h.send(SendCommand::Start {
                session_id: session_id.clone(),
                target,
                files,
                sender_alias: self.identity.fingerprint.clone(), // TODO: real alias
                sender_port,
                sender_https,
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

    fn cancel(&mut self) {
        if let (Some(h), Some(sid)) = (&self.handle, &self.session_id) {
            h.send(SendCommand::Cancel {
                session_id: sid.clone(),
            });
        }
        self.done = true;
        self.active = false;
        self.state_changed();
    }

    fn dismiss(&mut self) {
        self.session_id = None;
        self.active = false;
        self.done = false;
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
                SendEvent::FileProgress { file_id, progress, .. } => {
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
                SendEvent::Finished { ok, error, .. } => {
                    self.active = false;
                    self.done = true;
                    if !ok {
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