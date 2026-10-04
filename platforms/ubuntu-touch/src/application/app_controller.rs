// SPDX-License-Identifier: Apache-2.0
//
// Application layer between the Qt bridge and the shared Rust core.
//
// Rules:
//  - No Qt types here. This module must stay usable without Qt.
//  - No direct QObject mutation. Communicate with the bridge
//    via channels that the Qt side drains on the Qt thread.
//  - Do not modify packages/core. Use its public API only.
//    If something is missing, add an adapter here.

use std::sync::Arc;
use std::thread;

use tokio::runtime::Runtime;
use tokio::sync::mpsc;

/// Events flowing application -> bridge.
/// The bridge drains this on the Qt thread and turns them into
/// QObject signals / QAbstractListModel updates.
#[derive(Debug)]
pub enum AppEvent {
    Log(String),
    // Future: DevicesUpdated(Vec<Device>), TransferProgress(...), etc.
}

/// Commands flowing bridge -> application.
#[derive(Debug)]
pub enum AppCommand {
    StartDiscovery,
    StopDiscovery,
    Shutdown,
    // Future: SendFiles { device_id, paths }, CancelTransfer { id }, ...
}

/// Handle held by the Qt-side bridge.
/// Owns the Tokio runtime and the command channel.
pub struct AppControllerHandle {
    cmd_tx: mpsc::UnboundedSender<AppCommand>,
    // Runtime is kept alive for the lifetime of the handle.
    _rt: Arc<Runtime>,
}

impl AppControllerHandle {
    pub fn spawn() -> Self {
        let rt = Arc::new(
            Runtime::new().expect("failed to create Tokio runtime for AppController"),
        );

        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<AppCommand>();
        let (evt_tx, _evt_rx) = mpsc::unbounded_channel::<AppEvent>();

        // Long-running background task.
        // TODO: connect to existing LocalSend core API.
        //  - discovery::start(...)
        //  - server::start(...)
        //  - session::subscribe(...)
        // Replace the placeholder loop below with core wiring.
        let evt_tx_bg = evt_tx.clone();
        rt.spawn(async move {
            let _ = evt_tx_bg.send(AppEvent::Log(
                "application layer started (placeholder)".into(),
            ));
            while let Some(cmd) = cmd_rx.recv().await {
                match cmd {
                    AppCommand::StartDiscovery => {
                        let _ = evt_tx_bg.send(AppEvent::Log(
                            "StartDiscovery (TODO: wire to packages/core)".into(),
                        ));
                    }
                    AppCommand::StopDiscovery => {
                        let _ = evt_tx_bg.send(AppEvent::Log(
                            "StopDiscovery (TODO: wire to packages/core)".into(),
                        ));
                    }
                    AppCommand::Shutdown => {
                        let _ = evt_tx_bg.send(AppEvent::Log("shutdown".into()));
                        break;
                    }
                }
            }
        });

        // Keep event receiver movable to the bridge later.
        // For now we drop it; the bridge will subscribe in a follow-up commit.
        drop(_evt_rx);

        Self { cmd_tx, _rt: rt }
    }

    pub fn send(&self, cmd: AppCommand) {
        let _ = self.cmd_tx.send(cmd);
    }

    pub fn shutdown(&self) {
        let _ = self.cmd_tx.send(AppCommand::Shutdown);
    }
}

impl Drop for AppControllerHandle {
    fn drop(&mut self) {
        let _ = self.cmd_tx.send(AppCommand::Shutdown);
    }
}

/// Guard against accidentally running the app on the Qt thread.
/// Useful once real work is added.
#[allow(dead_code)]
fn assert_not_qt_thread() {
    if thread::current().name() == Some("qt") {
        panic!("application layer must not run on the Qt thread");
    }
}