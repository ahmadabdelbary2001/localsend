// SPDX-License-Identifier: Apache-2.0
//
// ServerController exposes the read-only server state required by ReceivePage.
// It is populated by the application layer (ServerHandle).
//
// TODO: connect to existing LocalSend core API.
// The core crate is expected to expose:
//   - server start/stop
//   - current alias / port / running flag
//   - bound local IPs
// Until that wiring is done, values are cached locally.

use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct ServerController {
    base: qt_base_class!(trait QObject),

    running: qt_property!(bool; NOTIFY state_changed),
    alias:   qt_property!(QString; NOTIFY state_changed),
    port:    qt_property!(u32; NOTIFY state_changed),
    /// Human-readable, newline-separated list of local IPs,
    /// e.g. "#abc123 192.168.1.42".
    local_ips_label: qt_property!(QString; NOTIFY state_changed),

    state_changed: qt_signal!(),
}

impl ServerController {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_snapshot(&mut self, running: bool, alias: String, port: u32, ips_label: String) {
        self.running = running;
        self.alias = QString::from(alias);
        self.port = port;
        self.local_ips_label = QString::from(ips_label);
        self.state_changed();
    }
}