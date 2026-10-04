// SPDX-License-Identifier: Apache-2.0
//
// ServerController: read-only server state for ReceivePage.
// Real server wiring lives in application::server_service (still stubbed).

use std::sync::Arc;
use std::sync::Mutex;

use qmetaobject::prelude::*;

use crate::application::server_service::{ServerCommand, ServerEvent, ServerHandle, ServerSnapshot};

#[derive(QObject)]
pub struct ServerController {
    base: qt_base_class!(trait QObject),

    running: qt_property!(bool; NOTIFY state_changed),
    alias:   qt_property!(QString; NOTIFY state_changed),
    port:    qt_property!(u32; NOTIFY state_changed),
    https:   qt_property!(bool; NOTIFY state_changed),

    state_changed: qt_signal!(),
    error_occurred: qt_signal!(message: QString),

    start: qt_method!(fn(&mut self, alias: QString, port: u32, https: bool)),
    stop: qt_method!(fn(&mut self)),
    restart: qt_method!(fn(&mut self, alias: QString, port: u32, https: bool)),

    /// Not exposed to QML.
    handle: Option<Arc<ServerHandle>>,
    /// The latest snapshot. Written from the bridge, read here.
    last: Arc<Mutex<ServerSnapshot>>,
}

impl ServerController {
    pub fn new() -> Self {
        let last = Arc::new(Mutex::new(ServerSnapshot::default()));
        let last_for_cb = last.clone();

        // NOTE: on_event is called on the server thread.
        // The Qt-object properties are NOT updated here directly;
        // the Qt side pulls them via poll(). This is a temporary design.
        // TODO: move to a QTimer-driven poll_events() as described in the plan.
        let handle = ServerHandle::spawn(move |evt| match evt {
            ServerEvent::Snapshot(s) => {
                if let Ok(mut g) = last_for_cb.lock() {
                    *g = s;
                }
            }
            ServerEvent::Error(e) => {
                log::warn!("server error: {e}");
            }
        });

        let mut this = Self {
            base: Default::default(),
            running: false,
            alias: QString::default(),
            port: 53317,
            https: true,
            state_changed: Default::default(),
            error_occurred: Default::default(),
            start: Default::default(),
            stop: Default::default(),
            restart: Default::default(),
            handle: Some(Arc::new(handle)),
            last,
        };
        this.refresh_from_last();
        this
    }

    /// Read the latest snapshot into Qt properties. Call from QML Timer for now.
    /// TODO: convert to a private Qt slot driven by a QTimer.
    fn refresh_from_last(&mut self) {
        let snap = self
            .last
            .lock()
            .map(|g| g.clone())
            .unwrap_or_default();
        let changed = snap.running != self.running
            || snap.alias != self.alias.to_string()
            || snap.port as u32 != self.port
            || snap.https != self.https;
        self.running = snap.running;
        self.alias = QString::from(snap.alias);
        self.port = snap.port as u32;
        self.https = snap.https;
        if changed {
            self.state_changed();
        }
    }

    fn start(&mut self, alias: QString, port: u32, https: bool) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Start {
                alias: alias.to_string(),
                port: port.min(u16::MAX as u32) as u16,
                https,
            });
        }
    }

    fn stop(&mut self) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Stop);
        }
    }

    fn restart(&mut self, alias: QString, port: u32, https: bool) {
        if let Some(h) = &self.handle {
            h.send(ServerCommand::Restart {
                alias: alias.to_string(),
                port: port.min(u16::MAX as u32) as u16,
                https,
            });
        }
    }
}