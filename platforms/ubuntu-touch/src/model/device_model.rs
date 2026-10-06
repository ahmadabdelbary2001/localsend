// SPDX-License-Identifier: Apache-2.0
//
// QAbstractListModel exposing discovered devices to QML.
// Fed from DiscoveryController.snapshot (updated on the Qt thread).

use qmetaobject::prelude::*;

use localsend::discovery::StatefulDevice;
use localsend::model::discovery::ProtocolType;

#[derive(QObject, Default)]
pub struct DeviceListModel {
    base: qt_base_class!(trait QAbstractListModel),

    items: Vec<StatefulDevice>,
}

impl DeviceListModel {
    pub fn new() -> Self {
        Self::default()
    }

    /// Replace the whole list. Called from the Qt thread, after
    /// DiscoveryController.poll() has a fresh snapshot.
    pub fn replace_all(&mut self, items: Vec<StatefulDevice>) {
        self.begin_reset_model();
        self.items = items;
        self.end_reset_model();
    }
}

impl QAbstractListModel for DeviceListModel {
    fn row_count(&self) -> i32 {
        self.items.len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let i = index.row() as usize;
        let Some(sd) = self.items.get(i) else {
            return QVariant::default();
        };
        let d = &sd.device;

        match role {
            0 => QString::from(d.fingerprint.clone()).into(),
            1 => QString::from(d.alias.clone()).into(),
            2 => QString::from(d.device_model.clone().unwrap_or_default()).into(),
            3 => QString::from(
                d.device_type
                    .as_ref()
                    .map(|dt| format!("{dt:?}").to_lowercase())
                    .unwrap_or_default(),
            )
            .into(),
            4 => {
                // ip (from best channel)
                let ip = sd
                    .get_best_channel()
                    .and_then(|c| c.http())
                    .map(|h| h.host.clone())
                    .unwrap_or_default();
                QString::from(ip).into()
            }
            5 => {
                let port = sd
                    .get_best_channel()
                    .and_then(|c| c.http())
                    .map(|h| h.port as i32)
                    .unwrap_or(0);
                QVariant::from(port)
            }
            6 => {
                let https = sd
                    .get_best_channel()
                    .and_then(|c| c.http())
                    .map(|h| h.protocol == ProtocolType::Https)
                    .unwrap_or(false);
                QVariant::from(https)
            }
            7 => QVariant::from(d.download),
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
        m
    }
}