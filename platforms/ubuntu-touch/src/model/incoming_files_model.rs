// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel for files in the current incoming transfer.
// Shares the entry list with ServerController via Arc<RwLock<...>>.
// QML calls `refresh()` after ServerController emits entriesChanged.

use std::sync::{Arc, RwLock};

use qmetaobject::prelude::*;

use crate::application::server_service::IncomingFileEntry;

#[derive(QObject)]
pub struct IncomingFilesModel {
    base: qt_base_class!(trait QAbstractListModel),

    /// Shared with ServerController.
    entries: Arc<RwLock<Vec<IncomingFileEntry>>>,

    /// Call after ServerController.poll() to reflect the shared state.
    refresh: qt_method!(fn(&mut self)),
}

impl IncomingFilesModel {
    pub fn new(entries: Arc<RwLock<Vec<IncomingFileEntry>>>) -> Self {
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

impl QAbstractListModel for IncomingFilesModel {
    fn row_count(&self) -> i32 {
        self.entries.read().map(|g| g.len() as i32).unwrap_or(0)
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let guard = match self.entries.read() {
            Ok(g) => g,
            Err(_) => return QVariant::default(),
        };
        let Some(e) = guard.get(i) else {
            return QVariant::default();
        };
        match role {
            0 => QString::from(e.file_name.clone()).into(),       // fileName
            1 => QVariant::from(e.size as i64),                    // size
            2 => QVariant::from(e.progress),                       // progress
            3 => QString::from(e.status.clone()).into(),           // status
            4 => QString::from(e.path.clone().unwrap_or_default()).into(), // path
            5 => QString::from(e.error.clone().unwrap_or_default()).into(), // error
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("fileName"));
        m.insert(1, QByteArray::from("size"));
        m.insert(2, QByteArray::from("progress"));
        m.insert(3, QByteArray::from("status"));
        m.insert(4, QByteArray::from("path"));
        m.insert(5, QByteArray::from("error"));
        m
    }
}