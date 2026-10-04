// SPDX-License-Identifier: Apache-2.0

#[allow(unused_imports)]
use localsend_ubuntu_touch::{
    application, bridge, model, platform, resources,
};

use std::cell::RefCell;
use std::process::ExitCode;
use std::sync::Arc;

use qmetaobject::prelude::*;
use qmetaobject::QObjectPinned;

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

    let settings = match SettingsService::load_or_default() {
        Ok(s) => Arc::new(s),
        Err(e) => {
            log::error!("failed to load settings: {e}");
            return ExitCode::FAILURE;
        }
    };

    resources::register();

    // QObjectPinned::new is unsafe because the underlying RefCell must
    // outlive any QML reference to the object. All RefCells below live
    // until `main` returns (after engine.exec()), so this invariant holds.
    let translator = RefCell::new(Translator::new());
    let app_controller = RefCell::new(AppController::new());
    let home_controller = RefCell::new(HomeController::new());
    let server_controller = RefCell::new(ServerController::new());
    let settings_controller = RefCell::new(SettingsController::new(settings));

    let mut engine = QmlEngine::new();

    unsafe {
        engine.set_object_property(
            "translator".into(),
            QObjectPinned::new(&translator),
        );
        engine.set_object_property(
            "appController".into(),
            QObjectPinned::new(&app_controller),
        );
        engine.set_object_property(
            "homeController".into(),
            QObjectPinned::new(&home_controller),
        );
        engine.set_object_property(
            "serverController".into(),
            QObjectPinned::new(&server_controller),
        );
        engine.set_object_property(
            "settingsController".into(),
            QObjectPinned::new(&settings_controller),
        );
    }

    engine.load_file("qrc:/qml/Main.qml".into());
    engine.exec();

    ExitCode::SUCCESS
}