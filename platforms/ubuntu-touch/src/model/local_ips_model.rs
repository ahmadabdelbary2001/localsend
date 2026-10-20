// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel for local IPv4 addresses.
// QML binds to this; `refresh()` re-enumerates interfaces (throttled) so a
// Wi-Fi change is picked up without restarting the app.

use std::sync::Arc;
use std::time::{Duration, Instant};

use qmetaobject::prelude::*;

use crate::application::local_ip_service::list_local_ips;
use crate::application::settings_service::SettingsService;

const REFRESH_INTERVAL: Duration = Duration::from_secs(2);

#[derive(QObject)]
pub struct LocalIpsModel {
    base: qt_base_class!(trait QAbstractListModel),

    items: Vec<String>,
    settings: Option<Arc<SettingsService>>,
    last_refresh: Instant,

    /// Re-enumerate interfaces (no-op if called more often than 2s).
    refresh: qt_method!(fn(&mut self)),
}

impl LocalIpsModel {
    pub fn new(settings: Arc<SettingsService>) -> Self {
        let snapshot = settings.snapshot();
        let items = list_local_ips(
            snapshot.network_whitelist.as_deref(),
            snapshot.network_blacklist.as_deref(),
        );
        Self {
            base: Default::default(),
            items,
            settings: Some(settings),
            last_refresh: Instant::now(),
            refresh: Default::default(),
        }
    }

    pub fn replace_all(&mut self, ips: Vec<String>) {
        if ips == self.items {
            return;
        }
        self.begin_reset_model();
        self.items = ips;
        self.end_reset_model();
    }

    pub fn refresh(&mut self) {
        if self.last_refresh.elapsed() < REFRESH_INTERVAL {
            return;
        }
        self.last_refresh = Instant::now();

        let Some(settings) = &self.settings else {
            return;
        };
        let snapshot = settings.snapshot();
        let ips = list_local_ips(
            snapshot.network_whitelist.as_deref(),
            snapshot.network_blacklist.as_deref(),
        );
        self.replace_all(ips);
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
