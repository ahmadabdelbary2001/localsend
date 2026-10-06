// SPDX-License-Identifier: Apache-2.0

#[allow(unused_imports)]
use localsend_ubuntu_touch::{application, bridge, model, platform, resources};

use std::cell::RefCell;
use std::process::ExitCode;
use std::sync::Arc;
use std::sync::RwLock;
use std::time::Duration;

use qmetaobject::prelude::*;
use qmetaobject::QObjectPinned;

use crate::application::discovery_service::{
    DiscoveryParams, DiscoveryServiceHandle,
};
use crate::application::identity_service::DeviceIdentity;
use crate::application::settings_service::SettingsService;
use crate::application::server_service::IncomingFileEntry;
use crate::bridge::app::AppController;
use crate::bridge::discovery_controller::DiscoveryController;
use crate::bridge::home_controller::HomeController;
use crate::bridge::server_controller::ServerController;
use crate::bridge::settings_controller::SettingsController;
use crate::bridge::translator::Translator;
use crate::bridge::send_controller::{OutgoingEntry, SendController};
use crate::model::local_ips_model::LocalIpsModel;
use crate::model::device_model::DeviceListModel;
use crate::model::incoming_files_model::IncomingFilesModel;
use crate::model::outgoing_files_model::OutgoingFilesModel;

fn main() -> ExitCode {
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

    // Shared discovery service. Both ServerController (to feed peers that
    // register with us) and DiscoveryController (to expose to QML) hold it.
    let discovery_handle = Arc::new(DiscoveryServiceHandle::spawn());

    resources::register();

    let translator = RefCell::new(Translator::new());
    let app_controller = RefCell::new(AppController::new());
    let home_controller = RefCell::new(HomeController::new());

    // Shared with ServerController and IncomingFilesModel.
    let incoming_entries: Arc<RwLock<Vec<IncomingFileEntry>>> =
        Arc::new(RwLock::new(Vec::new()));

    let outgoing_entries: Arc<RwLock<Vec<OutgoingEntry>>> = Arc::new(RwLock::new(Vec::new()));

    let server_controller = RefCell::new(ServerController::new(
        identity.clone(),
        discovery_handle.clone(),
        incoming_entries.clone(),
    ));

    let send_controller = RefCell::new(SendController::new(
        identity.clone(),
        discovery_handle.clone(),
        outgoing_entries.clone(),
    ));

    let settings_controller = RefCell::new(SettingsController::new(settings));
    let local_ips_model = RefCell::new(LocalIpsModel::new());
    let device_list_model = RefCell::new(DeviceListModel::new());
    let incoming_files_model = RefCell::new(IncomingFilesModel::new(incoming_entries.clone()));
    let outgoing_files_model = RefCell::new(OutgoingFilesModel::new(outgoing_entries.clone()));
    let discovery_controller = RefCell::new(DiscoveryController::new(
        discovery_handle.clone(),
    ));

    // Start server first.
    {
        let mut sc = server_controller.borrow_mut();
        sc.start_now(
            settings_snapshot.alias.clone(),
            settings_snapshot.port,
            settings_snapshot.https,
            settings_snapshot.receive_pin.clone(),
        );
    }

    // Start discovery.
    {
        let mut dc = discovery_controller.borrow_mut();
        dc.start_now(DiscoveryParams {
            alias: settings_snapshot.alias.clone(),
            port: settings_snapshot.port,
            https: settings_snapshot.https,
            fingerprint: identity.fingerprint.clone(),
            cert_pem: identity.certificate_pem.clone(),
            private_key_pem: identity.private_key_pem.clone(),
        });
    }

    // ---------- HEADLESS MODE ----------
    if std::env::var("LOCALSEND_HEADLESS").is_ok() {
        let auto_accept = std::env::var("LOCALSEND_AUTO_ACCEPT").is_ok();
        if auto_accept {
            let mut sc = server_controller.borrow_mut();
            sc.set_auto_accept(true);
            log::info!("auto-accept enabled");
        }

        log::info!("HEADLESS mode: server + discovery running. Ctrl+C to stop.");

        {
            let mut dc = discovery_controller.borrow_mut();
            dc.scan_now();
        }

        // ---- optional test send (fires once, after discovery settles) ----
        let test_send: Option<(String, String)> = std::env::var("LOCALSEND_TEST_SEND")
            .ok()
            .and_then(|s| {
                let mut parts = s.splitn(2, '|');
                let fp = parts.next()?.to_string();
                let path = parts.next()?.to_string();
                Some((fp, path))
            });
        let mut test_send_fired = false;
        let mut ticks: u32 = 0;

        let mut last_count: i32 = -1;
        loop {
            {
                let mut sc = server_controller.borrow_mut();
                sc.poll();
            }
            {
                let mut send_c = send_controller.borrow_mut();
                send_c.poll();
            }
            {
                let mut om = outgoing_files_model.borrow_mut();
                om.refresh();
            }
            {
                let mut dc = discovery_controller.borrow_mut();
                dc.poll();
                let c = dc.device_count();
                if c != last_count {
                    log::info!("devices: {}", c);
                    last_count = c;
                }
            }
            {
                let dc = discovery_controller.borrow();
                let mut dm = device_list_model.borrow_mut();
                dm.replace_all(dc.snapshot().to_vec());
            }
            {
                let mut im = incoming_files_model.borrow_mut();
                im.refresh();
            }

            // Fire TEST_SEND once, after 10 ticks (~5s) or when the target is visible.
            if !test_send_fired {
                ticks += 1;
                if let Some((fp, path)) = &test_send {
                    let target_visible = {
                        let dc = discovery_controller.borrow();
                        dc.snapshot().iter().any(|d| d.fingerprint == *fp)
                    };
                    if target_visible && ticks >= 4 {
                        log::info!("TEST_SEND: dispatching to {} -> {}", fp, path);
                        let paths_json = format!(
                            r#"["{}"]"#,
                            path.replace('\\', "\\\\")
                        );
                        let mut send_c = send_controller.borrow_mut();
                        send_c.send_files(
                            QString::from(fp.clone()),
                            QString::from(paths_json),
                        );
                        test_send_fired = true;
                    } else if ticks >= 40 {
                        log::warn!("TEST_SEND: giving up, target not visible");
                        test_send_fired = true;
                    }
                } else {
                    test_send_fired = true;
                }
            }

            std::thread::sleep(Duration::from_millis(500));
        }
    }

    if let Ok(env) = std::env::var("LOCALSEND_TEST_SEND") {
        let parts: Vec<&str> = env.splitn(2, '|').collect();
        if parts.len() == 2 {
            let fp = parts[0].to_string();
            let path = parts[1].to_string();
            log::info!("TEST_SEND: waiting 5s for discovery…");
            std::thread::sleep(Duration::from_secs(5));
            let paths_json = format!(r#"["{}"]"#, path.replace('\\', "\\\\"));
            let mut send_c = send_controller.borrow_mut();
            send_c.send_files(QString::from(fp), QString::from(paths_json));
            log::info!("TEST_SEND: dispatched");
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
        engine.set_object_property("discoveryController".into(), QObjectPinned::new(&discovery_controller));
        engine.set_object_property("deviceListModel".into(), QObjectPinned::new(&device_list_model));
        engine.set_object_property("incomingFilesModel".into(), QObjectPinned::new(&incoming_files_model));
        engine.set_object_property("outgoingFilesModel".into(), QObjectPinned::new(&outgoing_files_model));
        engine.set_object_property("sendController".into(), QObjectPinned::new(&send_controller));
    }

    engine.load_file("qrc:/qml/Main.qml".into());
    engine.exec();

    ExitCode::SUCCESS
}