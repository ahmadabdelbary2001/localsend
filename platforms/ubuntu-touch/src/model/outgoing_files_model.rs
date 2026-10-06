// SPDX-License-Identifier: Apache-2.0
use std::sync::{Arc, RwLock};

use qmetaobject::prelude::*;

use crate::bridge::send_controller::OutgoingEntry;

#[derive(QObject)]
pub struct OutgoingFilesModel {
    base: qt_base_class!(trait QAbstractListModel),
    entries: Arc<RwLock<Vec<OutgoingEntry>>>,
    refresh: qt_method!(fn(&mut self)),
}

impl OutgoingFilesModel {
    pub fn new(entries: Arc<RwLock<Vec<OutgoingEntry>>>) -> Self {
        Self {
            base: Default::default(),
            entries,
            refresh: Default::default(),
        }
    }
    pub fn refresh(&mut self) {
        self.begin_reset_model();
        self.end_reset_model();
    }
}

impl QAbstractListModel for OutgoingFilesModel {
    fn row_count(&self) -> i32 {
        self.entries.read().map(|g| g.len() as i32).unwrap_or(0)
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let g = match self.entries.read() { Ok(g) => g, Err(_) => return QVariant::default() };
        let Some(e) = g.get(i) else { return QVariant::default() };
        match role {
            0 => QString::from(e.name.clone()).into(),
            1 => QVariant::from(e.size as i64),
            2 => QVariant::from(e.progress),
            3 => QString::from(e.status.clone()).into(),
            4 => QString::from(e.error.clone().unwrap_or_default()).into(),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("fileName"));
        m.insert(1, QByteArray::from("size"));
        m.insert(2, QByteArray::from("progress"));
        m.insert(3, QByteArray::from("status"));
        m.insert(4, QByteArray::from("error"));
        m
    }
}