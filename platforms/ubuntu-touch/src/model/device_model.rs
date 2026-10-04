// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel for nearby devices.
// QML binds to this; it never parses JSON or talks to the network.

use qmetaobject::prelude::*;

#[derive(Clone, Debug, Default)]
pub struct DeviceEntry {
    pub id: String,
    pub alias: String,
    pub device_type: String,
    pub model: String,
    pub ip: String,
    pub favorite: bool,
    pub status: String,
}

#[derive(QObject, Default)]
pub struct DeviceModel {
    base: qt_base_class!(trait QAbstractListModel),

    items: Vec<DeviceEntry>,

    // ---- Roles (names must match QML usage) ----------------------------
    // id, alias, deviceType, model, ip, favorite, status

    // ---- Methods exposed to QML ----------------------------------------
    row_count: qt_method!(fn(&self) -> i32),
    get: qt_method!(fn(&self, row: i32) -> QString),

    // ---- Slots called from Rust (application layer) --------------------
    // We deliberately do NOT expose mutation to QML.
    // The bridge will call `replace_all` when new discovery results arrive.
}

impl DeviceModel {
    pub fn replace_all(&mut self, items: Vec<DeviceEntry>) {
        let _ = &self.items;
        self.begin_reset_model();
        self.items = items;
        self.end_reset_model();
    }

    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn get(&self, _row: i32) -> QString {
        // Placeholder; real implementation returns per-role data.
        QString::default()
    }
}

impl QAbstractListModel for DeviceModel {
    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let Some(d) = self.items.get(i) else {
            return QVariant::default();
        };
        match role {
            0 => QString::from(d.id.clone()).into(),
            1 => QString::from(d.alias.clone()).into(),
            2 => QString::from(d.device_type.clone()).into(),
            3 => QString::from(d.model.clone()).into(),
            4 => QString::from(d.ip.clone()).into(),
            5 => d.favorite.into(),
            6 => QString::from(d.status.clone()).into(),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("id"));
        m.insert(1, QByteArray::from("alias"));
        m.insert(2, QByteArray::from("deviceType"));
        m.insert(3, QByteArray::from("model"));
        m.insert(4, QByteArray::from("ip"));
        m.insert(5, QByteArray::from("favorite"));
        m.insert(6, QByteArray::from("status"));
        m
    }
}
