// SPDX-License-Identifier: Apache-2.0
//
// ServerController exposes server state to QML.
// It holds a ServerHandle and polls the event channel
// on the Qt thread (QML drives the polling via a Timer).

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::identity_service::DeviceIdentity;
use crate::application::server_service::{
    ServerCommand, ServerEvent, ServerHandle, ServerSnapshot,
};

#[derive(QObject)]
pub struct ServerController {
    base: qt_base_class!(trait QObject),

    running: qt_property!(bool; NOTIFY state_changed),
    alias: qt_property!(QString; NOTIFY state_changed),
    port: qt_property!(u32; NOTIFY state_changed),
    https: qt_property!(bool; NOTIFY state_changed),

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),

    start: qt_method!(fn(&mut self, alias: QString, port: u32, https: bool, pin: QString)),
    stop: qt_method!(fn(&mut self)),
    poll: qt_method!(fn(&mut self)),

    /// Not exposed to QML.
    handle: Option<Arc<ServerHandle>>,
    /// Last snapshot for change detection.
    last_snapshot: ServerSnapshot,
}

impl ServerController {
    pub fn new(identity: Arc<DeviceIdentity>) -> Self {
        let handle = ServerHandle::spawn(identity);
        Self {
            base: Default::default(),
            running: false,
            alias: QString::default(),
            port: 53317,
            https: true,
            state_changed: Default::default(),
            log_message: Default::default(),
            start: Default::default(),
            stop: Default::default(),
            poll: Default::default(),
            handle: Some(Arc::new(handle)),
            last_snapshot: ServerSnapshot::default(),
        }
    }

    fn start(&mut self, alias: QString, port: u32, https: bool, pin: QString) {
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

    fn stop(&mut self) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Stop);
        }
    }

    fn poll(&mut self) {
        let Some(h) = &self.handle else { return };

        loop {
            let Some(evt) = h.try_recv_event() else { break };
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
                ServerEvent::Log(msg) => {
                    log::info!("[server] {}", msg);
                    self.log_message(QString::from(msg));
                }
            }
        }
    }
}