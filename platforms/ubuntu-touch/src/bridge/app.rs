// SPDX-License-Identifier: Apache-2.0
//
// AppController is the single QObject the QML root binds to.
// It delegates all business work to application::AppController
// over a channel; the Qt thread never touches Tokio directly.

use cstr::cstr;
use qmetaobject::prelude::*;
use std::sync::Arc;

use crate::application::app_controller as app;

#[derive(QObject, Default)]
pub struct AppController {
    base: qt_base_class!(trait QObject),

    /// Human-readable status shown on the first screen.
    /// Real business state will move to dedicated models/controllers later.
    status: qt_property!(QString; NOTIFY status_changed),
    status_changed: qt_signal!(),

    /// Version of the Rust core, for diagnostics.
    core_version: qt_property!(QString; NOTIFY core_version_changed),
    core_version_changed: qt_signal!(),

    /// Called from QML after Component.onCompleted.
    initialize: qt_method!(fn(&mut self)),

    /// Placeholder to prove QML -> Rust -> application wiring works.
    /// The real send flow will be added in SendController.
    ping: qt_method!(fn(&mut self) -> QString),

    /// Background handle to the Rust application layer.
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
        log::info!("AppController initialized");
        self.status = QString::from("LocalSend ready");
        self.status_changed();
        self.core_version = QString::from("core: TODO(connect to packages/core)");
        self.core_version_changed();
    }

    fn ping(&mut self) -> QString {
        QString::from("pong from Rust")
    }
}