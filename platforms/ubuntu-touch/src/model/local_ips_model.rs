// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel for local IPv4 addresses.
// QML binds to this; the model is refreshed from Rust when needed.

use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct LocalIpsModel {
    base: qt_base_class!(trait QAbstractListModel),

    items: Vec<String>,
}

impl LocalIpsModel {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn replace_all(&mut self, ips: Vec<String>) {
        self.begin_reset_model();
        self.items = ips;
        self.end_reset_model();
    }
}

impl QAbstractListModel for LocalIpsModel {
    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let Some(ip) = self.items.get(i) else {
            return QVariant::default();
        };
        match role {
            // 0 -> "ip"
            0 => QString::from(ip.clone()).into(),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("ip"));
        m
    }
}