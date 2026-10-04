// SPDX-License-Identifier: Apache-2.0
//
// Application layer between the Qt bridge and the shared Rust core.
//
// Rules:
//  - No Qt types here.
//  - No direct QObject mutation. Events flow through channels
//    that the bridge drains.
//  - Do not modify packages/core. Use its public API only.

use std::sync::Arc;

use tokio::runtime::Runtime;
use tokio::sync::mpsc;

/// Events flowing application -> bridge.
#[derive(Debug)]
pub enum AppEvent {
    Log(String),
    /// Resolved (running, alias, port, ips_label) snapshot for ServerController.
    ServerSnapshot {
        running: bool,
        alias: String,
        port: u32,
        ips_label: String,
    },
}

/// Commands flowing bridge -> application.
#[derive(Debug)]
pub enum AppCommand {
    /// Equivalent to Flutter's `postInit`.
    PostInit,
    OnResumed,
    OnDetached,
    Shutdown,
}

pub struct AppControllerHandle {
    cmd_tx: mpsc::UnboundedSender<AppCommand>,
    evt_rx: std::sync::Mutex<Option<mpsc::UnboundedReceiver<AppEvent>>>,
    _rt: Arc<Runtime>,
}

impl AppControllerHandle {
    pub fn spawn() -> Self {
        let rt = Arc::new(Runtime::new().expect("failed to create Tokio runtime"));

        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<AppCommand>();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel::<AppEvent>();

        let evt_tx_bg = evt_tx.clone();
        rt.spawn(async move {
            let _ = evt_tx_bg.send(AppEvent::Log("application layer started".into()));

            while let Some(cmd) = cmd_rx.recv().await {
                match cmd {
                    AppCommand::PostInit => {
                        // TODO: connect to existing LocalSend core API.
                        //
                        // Expected adapter steps (do NOT edit packages/core):
                        //  1. Build a `CoreConfig` from SettingsService.
                        //  2. Call `core::server::start(cfg).await` and obtain a handle.
                        //  3. Call `core::discovery::start(cfg).await` and subscribe.
                        //  4. Subscribe to a `ServerEvents` stream to build
                        //     `AppEvent::ServerSnapshot` messages.
                        //
                        // For now we emit a placeholder snapshot so the UI is testable.
                        let _ = evt_tx_bg.send(AppEvent::ServerSnapshot {
                            running: false,
                            alias: "LocalSend (UT)".into(),
                            port: 53317,
                            ips_label: String::new(),
                        });
                    }
                    AppCommand::OnResumed => {
                        // TODO: re-init sockets and restart discovery.
                        // See Flutter's LifeCycleWatcher.resumed.
                    }
                    AppCommand::OnDetached => {
                        // TODO: dispose discovery handles.
                    }
                    AppCommand::Shutdown => break,
                }
            }
        });

        Self {
            cmd_tx,
            evt_rx: std::sync::Mutex::new(Some(evt_rx)),
            _rt: rt,
        }
    }

    pub fn post_init_async(&self) {
        let _ = self.cmd_tx.send(AppCommand::PostInit);
    }

    pub fn on_resumed(&self) {
        let _ = self.cmd_tx.send(AppCommand::OnResumed);
    }

    pub fn on_detached(&self) {
        let _ = self.cmd_tx.send(AppCommand::OnDetached);
    }

    /// Take the event receiver.
    ///
    /// NOTE: This is a temporary design for the skeleton.
    /// Once the Qt-side event dispatcher is in place, the receiver
    /// will be moved to a dedicated poller bound to the Qt thread
    /// (e.g. a QTimer-driven `AppController::poll_events`).
    pub fn take_event_receiver(
        &self,
    ) -> Option<mpsc::UnboundedReceiver<AppEvent>> {
        self.evt_rx.lock().ok().and_then(|mut g| g.take())
    }
}

impl Drop for AppControllerHandle {
    fn drop(&mut self) {
        let _ = self.cmd_tx.send(AppCommand::Shutdown);
    }
}