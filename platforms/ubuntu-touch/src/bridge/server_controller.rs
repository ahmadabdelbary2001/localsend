// SPDX-License-Identifier: Apache-2.0

use std::sync::{Arc, RwLock};

use qmetaobject::prelude::*;

use crate::application::discovery_service::{
    DiscoveryCommand, DiscoveryServiceHandle, build_discovered_device,
};
use crate::application::history_service::{HistoryEntry, HistoryService};
use crate::application::identity_service::DeviceIdentity;
use crate::application::server_service::{
    IncomingFileEntry, IncomingSession, ServerCommand, ServerEvent, ServerHandle, ServerSnapshot,
};

#[derive(QObject)]
pub struct ServerController {
    base: qt_base_class!(trait QObject),

    running: qt_property!(bool; NOTIFY state_changed),
    alias: qt_property!(QString; NOTIFY state_changed),
    port: qt_property!(u32; NOTIFY state_changed),
    https: qt_property!(bool; NOTIFY state_changed),

    incoming_active: qt_property!(bool; NOTIFY incoming_changed),
    incoming_phase: qt_property!(QString; NOTIFY incoming_changed), // "" | "waiting" | "receiving" | "done"
    incoming_sender: qt_property!(QString; NOTIFY incoming_changed),
    incoming_file_count: qt_property!(i32; NOTIFY incoming_changed),

    /// true while the HTTP server is running in web-receive (upload) mode.
    web_receive_active: qt_property!(bool; NOTIFY web_receive_changed),
    /// Port the web-receive server is listening on (0 when inactive).
    web_receive_port: qt_property!(u32; NOTIFY web_receive_changed),
    auto_accept: qt_property!(bool; NOTIFY auto_accept_changed),
    auto_accept_changed: qt_signal!(),

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),
    incoming_changed: qt_signal!(),
    entries_changed: qt_signal!(),
    web_receive_changed: qt_signal!(),

    start: qt_method!(fn(&mut self, alias: QString, port: u32, https: bool, pin: QString)),
    stop: qt_method!(fn(&mut self)),
    poll: qt_method!(fn(&mut self)),
    accept_incoming: qt_method!(fn(&mut self)),
    decline_incoming: qt_method!(fn(&mut self)),
    dismiss_incoming: qt_method!(fn(&mut self)),
    start_web_receive: qt_method!(fn(&mut self, alias: QString, port: u32, https: bool, pin: QString)),
    stop_web_receive: qt_method!(fn(&mut self)),
    set_auto_accept: qt_method!(fn(&mut self, v: bool)),

    handle: Option<Arc<ServerHandle>>,
    discovery: Option<Arc<DiscoveryServiceHandle>>,
    last_snapshot: ServerSnapshot,
    history: Arc<HistoryService>,
    current_session: Option<IncomingSession>,
    entries: Arc<RwLock<Vec<IncomingFileEntry>>>,
}

impl ServerController {
    pub fn new(
        identity: Arc<DeviceIdentity>,
        discovery: Arc<DiscoveryServiceHandle>,
        entries: Arc<RwLock<Vec<IncomingFileEntry>>>,
        history: Arc<HistoryService>,
    ) -> Self {
        let handle = ServerHandle::spawn(identity);
        Self {
            base: Default::default(),
            running: false,
            alias: QString::default(),
            port: 53317,
            https: true,
            incoming_active: false,
            incoming_phase: QString::default(),
            incoming_sender: QString::default(),
            incoming_file_count: 0,
            state_changed: Default::default(),
            log_message: Default::default(),
            incoming_changed: Default::default(),
            entries_changed: Default::default(),
            web_receive_changed: Default::default(),
            web_receive_active: false,
            web_receive_port: 0,
            auto_accept: false,
            auto_accept_changed: Default::default(),
            set_auto_accept: Default::default(),
            start: Default::default(),
            stop: Default::default(),
            poll: Default::default(),
            accept_incoming: Default::default(),
            decline_incoming: Default::default(),
            dismiss_incoming: Default::default(),
            start_web_receive: Default::default(),
            stop_web_receive: Default::default(),
            handle: Some(Arc::new(handle)),
            discovery: Some(discovery),
            last_snapshot: ServerSnapshot::default(),
            current_session: None,
            entries,
            history,
        }
    }

    pub fn start_now(&mut self, alias: String, port: u16, https: bool, pin: Option<String>) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Start {
                alias,
                port,
                https,
                pin,
                verify_checksums: false,
            });
        }
    }

    pub fn start(&mut self, alias: QString, port: u32, https: bool, pin: QString) {
        let pin_s = pin.to_string();
        let pin_opt = if pin_s.is_empty() { None } else { Some(pin_s) };
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Start {
                alias: alias.to_string(),
                port: port.min(u16::MAX as u32) as u16,
                https,
                pin: pin_opt,
                verify_checksums: false,
            });
        }
    }

    pub fn stop(&mut self) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Stop);
        }
        self.reset_incoming();
    }

    pub fn set_auto_accept(&mut self, v: bool) {
        self.auto_accept = v;
        self.auto_accept_changed();
        if let Some(h) = &self.handle {
            h.send(ServerCommand::SetAutoAccept(v));
        }
    }

    fn reset_incoming(&mut self) {
        self.current_session = None;
        if let Ok(mut g) = self.entries.write() {
            g.clear();
        }
        self.incoming_active = false;
        self.incoming_phase = QString::default();
        self.incoming_sender = QString::default();
        self.incoming_file_count = 0;
        self.entries_changed();
        self.incoming_changed();
    }

    pub fn accept_incoming(&mut self) {
        let Some(s) = self.current_session.clone() else {
            return;
        };
        if let Some(h) = &self.handle {
            h.send(ServerCommand::AcceptUpload {
                session_id: s.session_id.clone(),
            });
        }
        self.incoming_phase = QString::from("receiving");
        self.incoming_changed();
    }

    pub fn decline_incoming(&mut self) {
        let Some(s) = self.current_session.clone() else {
            return;
        };
        if let Some(h) = &self.handle {
            h.send(ServerCommand::DeclineUpload {
                session_id: s.session_id.clone(),
            });
        }
        self.reset_incoming();
    }

    pub fn dismiss_incoming(&mut self) {
        self.reset_incoming();
    }

    pub fn start_web_receive(&mut self, alias: QString, port: u32, https: bool, pin: QString) {
        let pin_s = pin.to_string();
        let pin_opt = if pin_s.is_empty() { None } else { Some(pin_s) };
        if let Some(h) = &self.handle {
            h.send(ServerCommand::StartWebReceive {
                alias: alias.to_string(),
                port: port.min(u16::MAX as u32) as u16,
                https,
                pin: pin_opt,
            });
        }
    }

    pub fn stop_web_receive(&mut self) {
        // Stop the server (returns to normal receive mode) by sending Stop
        // then immediately restarting as regular server.
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Stop);
        }
        self.web_receive_active = false;
        self.web_receive_port = 0;
        self.web_receive_changed();
    }

    pub fn poll(&mut self) {
        // Pull all events into a Vec so we can freely borrow `self` while
        // processing them. Drains the channel first, then handles.
        let events: Vec<ServerEvent> = {
            let Some(h) = &self.handle else { return };
            let mut out = Vec::new();
            while let Some(evt) = h.try_recv_event() {
                out.push(evt);
            }
            out
        };

        for evt in events {
            match evt {
                ServerEvent::Snapshot(snap) => {
                    let changed = snap.running != self.running
                        || snap.alias != self.alias.to_string()
                        || (snap.port as u32) != self.port
                        || snap.https != self.https;
                    self.last_snapshot = snap.clone();
                    self.running = snap.running;
                    self.alias = QString::from(snap.alias);
                    self.port = snap.port as u32;
                    self.https = snap.https;
                    if changed {
                        self.state_changed();
                    }
                }
                ServerEvent::Register { ip, info } => {
                    if let Some(dh) = &self.discovery {
                        let device = build_discovered_device(
                            info.alias,
                            info.version,
                            info.device_model,
                            info.device_type,
                            info.fingerprint,
                            ip,
                            info.port,
                            info.protocol,
                            info.download,
                        );
                        dh.send(DiscoveryCommand::AddDevice(device));
                    }
                }
                ServerEvent::PrepareUpload(session) => {
                    self.current_session = Some(session.clone());
                    self.incoming_sender = QString::from(session.sender_alias.clone());
                    self.incoming_file_count = session.files.len() as i32;
                    self.incoming_phase = QString::from("waiting");
                    self.incoming_active = true;

                    if let Ok(mut g) = self.entries.write() {
                        g.clear();
                        for f in &session.files {
                            g.push(IncomingFileEntry {
                                file_id: f.file_id.clone(),
                                file_name: f.file_name.clone(),
                                size: f.size,
                                progress: 0.0,
                                status: "queue".into(),
                                path: None,
                                error: None,
                            });
                        }
                    }
                    self.entries_changed();
                    self.incoming_changed();
                    self.log_message(QString::from(format!(
                        "Incoming: {} file(s) from {}",
                        session.files.len(),
                        session.sender_alias
                    )));
                }
                ServerEvent::PrepareUploadAborted { session_id } => {
                    log::info!("[server] prepare-upload aborted: {session_id}");
                    self.reset_incoming();
                }
                ServerEvent::FileUploadStarted { file_id, .. } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.status = "sending".into();
                        }
                    }
                    self.entries_changed();
                }
                ServerEvent::FileUploadProgress {
                    file_id, progress, ..
                } => {
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.progress = progress;
                        }
                    }
                    self.entries_changed();
                }
                ServerEvent::FileUploadResult {
                    file_id,
                    path,
                    error,
                    ..
                } => {
                    let mut recorded: Option<(String, u64, String)> = None;
                    if let Ok(mut g) = self.entries.write() {
                        if let Some(e) = g.iter_mut().find(|e| e.file_id == file_id) {
                            e.progress = 1.0;
                            match (&path, &error) {
                                (Some(p), _) => {
                                    e.status = "finished".into();
                                    e.path = Some(p.clone());
                                    recorded = Some((e.file_name.clone(), e.size, p.clone()));
                                }
                                (None, Some(err)) => {
                                    e.status = "failed".into();
                                    e.error = Some(err.clone());
                                }
                                (None, None) => {
                                    e.status = "failed".into();
                                    e.error = Some("unknown".into());
                                }
                            }
                        }
                    }
                    if let Some((name, size, p)) = recorded {
                        let alias = self
                            .current_session
                            .as_ref()
                            .map(|s| s.sender_alias.clone())
                            .unwrap_or_default();
                        self.history
                            .add(HistoryEntry::new(name, size, Some(p), alias, false));
                    }
                    self.entries_changed();
                }
                ServerEvent::SessionEnd { cancelled, .. } => {
                    self.incoming_phase = QString::from("done");
                    self.incoming_changed();
                    self.log_message(QString::from(format!(
                        "Session ended{}",
                        if cancelled { " (cancelled)" } else { "" }
                    )));
                }
                ServerEvent::Log(msg) => {
                    log::info!("[server] {}", msg);
                    self.log_message(QString::from(msg));
                }
                ServerEvent::WebReceiveChanged { active, port } => {
                    self.web_receive_active = active;
                    self.web_receive_port = port as u32;
                    self.web_receive_changed();
                }
            }
        }
    }
}
