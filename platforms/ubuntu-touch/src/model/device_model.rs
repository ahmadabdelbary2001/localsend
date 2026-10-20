// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel for nearby devices.
// Reads directly from the shared Vec maintained by
// application::discovery_service, so it stays in sync with Rust
// without copying on every poll.
//
// The view is only reset when the device list actually changed; a reset
// recreates every delegate, so doing it on every poll tick made the list
// flicker and killed scroll position.

use std::sync::{Arc, RwLock};

use qmetaobject::prelude::*;

use crate::application::discovery_service::DeviceSnapshot;

#[derive(QObject)]
pub struct DeviceListModel {
    base: qt_base_class!(trait QAbstractListModel),

    count: qt_property!(i32; NOTIFY count_changed),
    count_changed: qt_signal!(),

    /// Shared with DiscoveryServiceHandle.
    items: Arc<RwLock<Vec<DeviceSnapshot>>>,

    /// Last snapshot the view has been reset for.
    last: Vec<DeviceSnapshot>,

    /// Called from QML after discoveryController.poll() to force
    /// the view to re-read the shared Vec.
    refresh: qt_method!(fn(&mut self)),
}

impl DeviceListModel {
    pub fn new(items: Arc<RwLock<Vec<DeviceSnapshot>>>) -> Self {
        let last = items.read().map(|g| g.clone()).unwrap_or_default();
        let count = last.len() as i32;
        Self {
            base: Default::default(),
            count,
            count_changed: Default::default(),
            items,
            last,
            refresh: Default::default(),
        }
    }

    pub fn refresh(&mut self) {
        let snapshot = self.items.read().map(|g| g.clone()).unwrap_or_default();
        let count = snapshot.len() as i32;

        if snapshot != self.last {
            self.begin_reset_model();
            self.last = snapshot;
            self.end_reset_model();
        }

        if self.count != count {
            self.count = count;
            self.count_changed();
        }
    }
}

impl QAbstractListModel for DeviceListModel {
    fn row_count(&self) -> i32 {
        self.items.read().map(|g| g.len() as i32).unwrap_or(0)
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let g = match self.items.read() {
            Ok(g) => g,
            Err(_) => return QVariant::default(),
        };
        let Some(d) = g.get(i) else {
            return QVariant::default();
        };
        match role {
            0 => QString::from(d.fingerprint.clone()).into(),
            1 => QString::from(d.alias.clone()).into(),
            2 => QString::from(d.device_model.clone().unwrap_or_default()).into(),
            3 => QString::from(d.device_type.clone().unwrap_or_default()).into(),
            4 => QString::from(d.ip.clone()).into(),
            5 => QVariant::from(d.port as i32),
            6 => QVariant::from(d.https),
            7 => QVariant::from(d.download),
            8 => QString::from(d.version.clone()).into(),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("fingerprint"));
        m.insert(1, QByteArray::from("alias"));
        m.insert(2, QByteArray::from("deviceModel"));
        m.insert(3, QByteArray::from("deviceType"));
        m.insert(4, QByteArray::from("ip"));
        m.insert(5, QByteArray::from("port"));
        m.insert(6, QByteArray::from("https"));
        m.insert(7, QByteArray::from("download"));
        m.insert(8, QByteArray::from("version"));
        m
    }
}
