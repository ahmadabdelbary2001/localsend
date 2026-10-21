// SPDX-License-Identifier: Apache-2.0
//
// DiscoveryController exposes discovery to QML.
// Its `snapshot` field is read by DeviceListModel to populate the view.

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::discovery_service::{
    DeviceSnapshot, DiscoveryCommand, DiscoveryEvent, DiscoveryParams, DiscoveryServiceHandle,
};

#[derive(QObject)]
pub struct DiscoveryController {
    base: qt_base_class!(trait QObject),

    running: qt_property!(bool; NOTIFY state_changed),
    scanning: qt_property!(bool; NOTIFY state_changed),
    device_count: qt_property!(i32; NOTIFY state_changed),
    /// The discovered devices as a JSON array. QML bindings that look up a
    /// device by fingerprint depend on this property, so they are re-evaluated
    /// when a peer is discovered or refreshed.
    devices_json: qt_property!(QString; NOTIFY state_changed),

    state_changed: qt_signal!(),
    log_message: qt_signal!(message: QString),

    start: qt_method!(
        fn(
            &mut self,
            alias: QString,
            port: u32,
            https: bool,
            fingerprint: QString,
            cert_pem: QString,
            private_key_pem: QString,
        )
    ),
    scan_now: qt_method!(fn(&mut self)),
    stop: qt_method!(fn(&mut self)),
    poll: qt_method!(fn(&mut self)),


    /// Public for DeviceListModel.
    pub snapshot: Vec<DeviceSnapshot>,

    handle: Option<Arc<DiscoveryServiceHandle>>,
}

impl DiscoveryController {
    pub fn new(handle: Arc<DiscoveryServiceHandle>) -> Self {
        Self {
            base: Default::default(),
            running: false,
            scanning: false,
            device_count: 0,
            devices_json: QString::default(),
            state_changed: Default::default(),
            log_message: Default::default(),
            start: Default::default(),
            scan_now: Default::default(),
            stop: Default::default(),
            poll: Default::default(),
            snapshot: Vec::new(),
            handle: Some(handle),
        }
    }

    /// Rust-only entry used from main.rs.
    pub fn start_now(&mut self, params: DiscoveryParams) {
        if let Some(h) = &self.handle {
            h.send(DiscoveryCommand::Start(params));
        }
        self.running = true;
        self.state_changed();
    }

    fn start(
        &mut self,
        alias: QString,
        port: u32,
        https: bool,
        fingerprint: QString,
        cert_pem: QString,
        private_key_pem: QString,
    ) {
        self.start_now(DiscoveryParams {
            alias: alias.to_string(),
            port: port.min(u16::MAX as u32) as u16,
            https,
            fingerprint: fingerprint.to_string(),
            cert_pem: cert_pem.to_string(),
            private_key_pem: private_key_pem.to_string(),
        });
    }

    pub fn scan_now(&mut self) {
        if let Some(h) = &self.handle {
            h.send(DiscoveryCommand::ScanNow);
        }
        self.scanning = true;
        self.state_changed();
    }

    fn stop(&mut self) {
        if let Some(h) = &self.handle {
            h.send(DiscoveryCommand::Stop);
        }
    }

    pub fn poll(&mut self) {
        let Some(h) = &self.handle else { return };
        let mut changed = false;
        loop {
            let Some(evt) = h.try_recv_event() else { break };
            match evt {
                DiscoveryEvent::DevicesChanged(snaps) => {
                    self.snapshot = snaps;
                    self.device_count = self.snapshot.len() as i32;
                    self.scanning = false;
                    self.devices_json = QString::from(self.snapshot_json());
                    changed = true;
                }
                DiscoveryEvent::Log(msg) => {
                    log::info!("[discovery] {}", msg);
                    self.log_message(QString::from(msg));
                }
            }
        }
        if changed {
            self.state_changed();
        }
    }

    /// Rust-only getter for the current device count.
    pub fn device_count(&self) -> i32 {
        self.device_count
    }

    /// The snapshot as a JSON array.
    ///
    /// The favorites list shows devices that are not necessarily online, so it
    /// needs the current model / type / address of a peer. QML cannot query
    /// the list model by fingerprint, so the whole snapshot is exposed here.
    fn snapshot_json(&self) -> String {
        let devices: Vec<serde_json::Value> = self
            .snapshot
            .iter()
            .map(|d| {
                serde_json::json!({
                    "fingerprint": d.fingerprint,
                    "alias": d.alias,
                    "deviceModel": d.device_model.clone().unwrap_or_default(),
                    "deviceType": d.device_type.clone().unwrap_or_default(),
                    "ip": d.ip,
                    "port": d.port,
                    "https": d.https,
                    "version": d.version,
                })
            })
            .collect();
        serde_json::to_string(&devices).unwrap_or_else(|_| "[]".into())
    }

    /// Rust-only accessor for the current snapshot (updated on poll).
    pub fn snapshot(&self) -> &[DeviceSnapshot] {
        &self.snapshot
    }
}
