// SPDX-License-Identifier: Apache-2.0

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::history_service::{HistoryEntry, HistoryService};

#[derive(QObject)]
pub struct HistoryController {
    base: qt_base_class!(trait QAbstractListModel),

    service: Arc<HistoryService>,
    items: Vec<HistoryEntry>,

    count: qt_property!(i32; NOTIFY changed),
    changed: qt_signal!(),

    remove: qt_method!(fn(&mut self, id: QString)),
    clear: qt_method!(fn(&mut self)),
    refresh: qt_method!(fn(&mut self)),
}

impl HistoryController {
    pub fn new(service: Arc<HistoryService>) -> Self {
        let items = service.snapshot();
        let count = items.len() as i32;
        Self {
            base: Default::default(),
            service,
            items,
            count,
            changed: Default::default(),
            remove: Default::default(),
            clear: Default::default(),
            refresh: Default::default(),
        }
    }

    /// Called from the Rust side (ServerController) after a successful receive.
    pub fn record(&mut self, entry: HistoryEntry) {
        self.service.add(entry);
        self.reload();
    }

    fn remove(&mut self, id: QString) {
        if self.service.remove(&id.to_string()) {
            self.reload();
        }
    }

    fn clear(&mut self) {
        if self.service.clear() {
            self.reload();
        }
    }

    pub fn refresh(&mut self) {
        self.reload();
    }

    fn reload(&mut self) {
        self.begin_reset_model();
        self.items = self.service.snapshot();
        self.end_reset_model();
        self.count = self.items.len() as i32;
        self.changed();
    }
}

impl QAbstractListModel for HistoryController {
    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let Some(e) = self.items.get(i) else {
            return QVariant::default();
        };
        match role {
            0 => QString::from(e.id.clone()).into(),
            1 => QString::from(e.file_name.clone()).into(),
            2 => QVariant::from(e.file_size as i64),
            3 => QString::from(e.path.clone().unwrap_or_default()).into(),
            4 => QString::from(e.sender_alias.clone()).into(),
            5 => QVariant::from(e.timestamp as i64),
            6 => QVariant::from(e.is_message),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("id"));
        m.insert(1, QByteArray::from("fileName"));
        m.insert(2, QByteArray::from("fileSize"));
        m.insert(3, QByteArray::from("path"));
        m.insert(4, QByteArray::from("senderAlias"));
        m.insert(5, QByteArray::from("timestamp"));
        m.insert(6, QByteArray::from("isMessage"));
        m
    }
}
