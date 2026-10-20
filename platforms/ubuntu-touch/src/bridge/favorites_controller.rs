// SPDX-License-Identifier: Apache-2.0
//
// FavoritesController is both a QAbstractListModel (for display)
// and a mutator (add/remove/update alias).

use std::sync::Arc;

use qmetaobject::prelude::*;

use crate::application::favorites_service::{Favorite, FavoritesService};

#[derive(QObject)]
pub struct FavoritesController {
    base: qt_base_class!(trait QAbstractListModel),

    service: Arc<FavoritesService>,
    items: Vec<Favorite>,

    count: qt_property!(i32; NOTIFY changed),
    changed: qt_signal!(),

    add_or_update:
        qt_method!(fn(&mut self, fingerprint: QString, ip: QString, port: u32, alias: QString)),
    remove: qt_method!(fn(&mut self, fingerprint: QString)),
    rename: qt_method!(fn(&mut self, fingerprint: QString, alias: QString)),
    is_favorite: qt_method!(fn(&self, fingerprint: QString) -> bool),
    alias_for: qt_method!(fn(&self, fingerprint: QString) -> QString),
    refresh: qt_method!(fn(&mut self)),
}

impl FavoritesController {
    pub fn new(service: Arc<FavoritesService>) -> Self {
        let items = service.snapshot();
        let count = items.len() as i32;
        Self {
            base: Default::default(),
            service,
            items,
            count,
            changed: Default::default(),
            add_or_update: Default::default(),
            remove: Default::default(),
            rename: Default::default(),
            is_favorite: Default::default(),
            alias_for: Default::default(),
            refresh: Default::default(),
        }
    }

    fn add_or_update(&mut self, fingerprint: QString, ip: QString, port: u32, alias: QString) {
        let fp = fingerprint.to_string();
        if self.service.is_favorite(&fp) {
            return;
        }
        let fav = Favorite::new(
            fp,
            ip.to_string(),
            port.min(u16::MAX as u32) as u16,
            alias.to_string(),
        );
        self.service.add(fav);
        self.reload();
    }

    fn remove(&mut self, fingerprint: QString) {
        if self.service.remove_by_fingerprint(&fingerprint.to_string()) {
            self.reload();
        }
    }

    fn rename(&mut self, fingerprint: QString, alias: QString) {
        if self
            .service
            .update_alias(&fingerprint.to_string(), alias.to_string())
        {
            self.reload();
        }
    }

    fn is_favorite(&self, fingerprint: QString) -> bool {
        self.service.is_favorite(&fingerprint.to_string())
    }

    fn alias_for(&self, fingerprint: QString) -> QString {
        let fp = fingerprint.to_string();
        match self.service.find(&fp) {
            Some(f) if f.custom_alias => QString::from(f.alias),
            _ => QString::default(),
        }
    }

    pub fn refresh(&mut self) {
        self.reload();
    }

    fn reload(&mut self) {
        let snapshot = self.service.snapshot();
        if snapshot != self.items {
            self.begin_reset_model();
            self.items = snapshot;
            self.end_reset_model();
        }
        self.count = self.items.len() as i32;
        self.changed();
    }
}

impl QAbstractListModel for FavoritesController {
    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let Some(f) = self.items.get(i) else {
            return QVariant::default();
        };
        match role {
            0 => QString::from(f.fingerprint.clone()).into(),
            1 => QString::from(f.alias.clone()).into(),
            2 => QString::from(f.ip.clone()).into(),
            3 => QVariant::from(f.port as i32),
            4 => QVariant::from(true), // isFavorite (always true in this list)
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut m = std::collections::HashMap::new();
        m.insert(0, QByteArray::from("fingerprint"));
        m.insert(1, QByteArray::from("alias"));
        m.insert(2, QByteArray::from("ip"));
        m.insert(3, QByteArray::from("port"));
        m.insert(4, QByteArray::from("isFavorite"));
        m
    }
}
