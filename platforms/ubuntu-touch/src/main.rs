// SPDX-License-Identifier: Apache-2.0

#[allow(unused_imports)]
use localsend_ubuntu_touch::{application, bridge, model, platform, resources};

use std::cell::RefCell;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use qmetaobject::prelude::*;
use qmetaobject::QObjectPinned;

use crate::application::identity_service::DeviceIdentity;
use crate::application::settings_service::SettingsService;
use crate::bridge::app::AppController;
use crate::bridge::home_controller::HomeController;
use crate::bridge::server_controller::ServerController;
use crate::bridge::settings_controller::SettingsController;
use crate::bridge::translator::Translator;
use crate::model::local_ips_model::LocalIpsModel;

fn main() -> ExitCode {
    // env_logger reads `log::*` records; tracing-log forwards `tracing::*`
    // records from `localsend` core into the same logger.
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info"),
    )
    .init();
    let _ = tracing_log::LogTracer::init();

    let settings = match SettingsService::load_or_default() {
        Ok(s) => Arc::new(s),
        Err(e) => {
            log::error!("failed to load settings: {e}");
            return ExitCode::FAILURE;
        }
    };

    let identity = match DeviceIdentity::load_or_generate() {
        Ok(id) => Arc::new(id),
        Err(e) => {
            log::error!("failed to load device identity: {e}");
            return ExitCode::FAILURE;
        }
    };

    let settings_snapshot = settings.snapshot();

    resources::register();

    let translator = RefCell::new(Translator::new());
    let app_controller = RefCell::new(AppController::new());
    let home_controller = RefCell::new(HomeController::new());
    let server_controller = RefCell::new(ServerController::new(identity));
    let settings_controller = RefCell::new(SettingsController::new(settings));
    let local_ips_model = RefCell::new(LocalIpsModel::new());

    // Start the server before any QML work, so a QML failure
    // does not prevent the server from running.
    {
        let mut sc = server_controller.borrow_mut();
        sc.start_now(
            settings_snapshot.alias.clone(),
            settings_snapshot.port,
            settings_snapshot.https,
            settings_snapshot.receive_pin.clone(),
        );
    }

    // ---------- HEADLESS MODE ----------
    if std::env::var("LOCALSEND_HEADLESS").is_ok() {
        log::info!("HEADLESS mode: server starting, Ctrl+C to stop.");
        // Drain server events forever, so log/errors are visible.
        loop {
            {
                let mut sc = server_controller.borrow_mut();
                sc.poll();
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    }

    let mut engine = QmlEngine::new();

    unsafe {
        engine.set_object_property("translator".into(), QObjectPinned::new(&translator));
        engine.set_object_property("appController".into(), QObjectPinned::new(&app_controller));
        engine.set_object_property("homeController".into(), QObjectPinned::new(&home_controller));
        engine.set_object_property("serverController".into(), QObjectPinned::new(&server_controller));
        engine.set_object_property("settingsController".into(), QObjectPinned::new(&settings_controller));
        engine.set_object_property("localIpsModel".into(), QObjectPinned::new(&local_ips_model));
    }

    engine.load_file("qrc:/qml/Main.qml".into());
    engine.exec();

    ExitCode::SUCCESS
}