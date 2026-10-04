// SPDX-License-Identifier: Apache-2.0
//
// AppController is the root QObject exposed to QML.
// It owns the handle to the application layer (Tokio side)
// and forwards lifecycle/state to sub-controllers.

use std::sync::Arc;

use cstr::cstr;
use qmetaobject::prelude::*;

use crate::application::app_controller as app;

#[derive(QObject, Default)]
pub struct AppController {
    base: qt_base_class!(trait QObject),

    /// Human-readable version string of the Rust core, for diagnostics.
    core_version: qt_property!(QString; NOTIFY core_version_changed),
    core_version_changed: qt_signal!(),

    /// Short status text. Will be replaced by fine-grained models
    /// once Server/Send/Settings controllers are fully wired.
    status: qt_property!(QString; NOTIFY status_changed),
    status_changed: qt_signal!(),

    /// Called once from QML after Component.onCompleted.
    initialize: qt_method!(fn(&mut self)),

    /// Placeholder slot that proves the QML -> Rust path works.
    ping: qt_method!(fn(&mut self) -> QString),

    /// Not exposed to QML.
    #[qt_property(QString, NOTIFY status_changed, READ only)]
    inner: Option<Arc<app::AppControllerHandle>>,
}

impl AppController {
    pub fn new() -> Self {
        let mut this = Self::default();
        this.inner = Some(Arc::new(app::AppControllerHandle::spawn()));
        this
    }

    fn initialize(&mut self) {
        log::info!("AppController::initialize");

        if let Some(h) = &self.inner {
            h.post_init_async();
        }

        self.status = QString::from("LocalSend ready");
        self.status_changed();

        self.core_version = QString::from(env!("CARGO_PKG_VERSION"));
        self.core_version_changed();
    }

    fn ping(&mut self) -> QString {
        QString::from("pong from Rust")
    }
}