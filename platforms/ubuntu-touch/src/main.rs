// SPDX-License-Identifier: Apache-2.0

mod application;
mod bridge;
mod model;
mod platform;
mod resources;

use std::env;
use std::process::ExitCode;

use cstr::cstr;
use qmetaobject::prelude::*;

use crate::bridge::app::AppController;

fn main() -> ExitCode {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    // QML resources are embedded in the binary.
    resources::register();

    // Boot QML engine on the Qt thread.
    let mut engine = QmlEngine::new();

    // Expose the application bridge to QML.
    // QObject names below are the ones QML imports.
    engine.set_object_property(
        cstr!("appController").into(),
        QObject::cpp_construct(&AppController::new()),
    );

    // Entry QML file (see resources.rs for the qrc path).
    engine.load_file(cstr!("qrc:/qml/Main.qml").into());
    engine.exec();

    ExitCode::SUCCESS
}