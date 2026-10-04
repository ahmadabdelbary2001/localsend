// SPDX-License-Identifier: Apache-2.0

mod application;
mod bridge;
mod model;
mod platform;
mod resources;

use std::process::ExitCode;

use cstr::cstr;
use qmetaobject::prelude::*;

use crate::bridge::app::AppController;
use crate::bridge::home_controller::HomeController;
use crate::bridge::server_controller::ServerController;
use crate::bridge::settings_controller::SettingsController;

fn main() -> ExitCode {
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info"),
    )
    .init();

    resources::register();

    let mut engine = QmlEngine::new();

    // Root controllers exposed to QML as top-level names.
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
    engine.set_object_property(
        cstr!("settingsController").into(),
        QObject::cpp_construct(&SettingsController::new()),
    );

    engine.load_file(cstr!("qrc:/qml/Main.qml").into());
    engine.exec();

    ExitCode::SUCCESS
}