// SPDX-License-Identifier: Apache-2.0

mod application;
mod bridge;
mod model;
mod platform;
mod resources;

use std::process::ExitCode;
use std::sync::Arc;

use cstr::cstr;
use qmetaobject::prelude::*;

use crate::application::settings_service::SettingsService;
use crate::bridge::app::AppController;
use crate::bridge::home_controller::HomeController;
use crate::bridge::server_controller::ServerController;
use crate::bridge::settings_controller::SettingsController;
use crate::bridge::translator::Translator;

fn main() -> ExitCode {
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info"),
    )
    .init();

    // Settings must be loaded before any QObject that reads them.
    // (Currently only SettingsController does, but wiring will grow.)
    let settings = match SettingsService::load_or_default() {
        Ok(s) => Some(Arc::new(s)),
        Err(e) => {
            log::error!("failed to load settings: {e}");
            None
        }
    };

    resources::register();

    let mut engine = QmlEngine::new();

    // Translator is always available.
    engine.set_object_property(
        cstr!("translator").into(),
        QObject::cpp_construct(&Translator::new()),
    );

    engine.set_object_property(
        cstr!("appController").into(),
        QObject::cpp_construct(&AppController::new()),
    );
    engine.set_object_property(
        cstr!("homeController").into(),
        QObject::cpp_construct(&HomeController::new()),
    );
    engine.set_object_property(
        cstr!("serverController").into(),
        QObject::cpp_construct(&ServerController::new()),
    );

    if let Some(svc) = settings {
        engine.set_object_property(
            cstr!("settingsController").into(),
            QObject::cpp_construct(&SettingsController::new(svc)),
        );
    } else {
        // Still expose the controller with defaults so QML doesn't break.
        engine.set_object_property(
            cstr!("settingsController").into(),
            QObject::cpp_construct(&SettingsController::new(Arc::new(
                SettingsService::load_or_default().unwrap_or_else(|_| {
                    // Best-effort fallback; load_or_default never fails
                    // silently without a config dir, so this is defensive.
                    panic!("no config dir and no fallback")
                }),
            ))),
        );
    }

    engine.load_file(cstr!("qrc:/qml/Main.qml").into());
    engine.exec();

    ExitCode::SUCCESS
}