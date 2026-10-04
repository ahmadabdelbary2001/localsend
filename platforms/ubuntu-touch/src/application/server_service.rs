// SPDX-License-Identifier: Apache-2.0
//
// Application-layer server service.
//
// Structure only for now. The real wiring to `localsend::http::server`
// will be added once we know the exact API surface. Until then, the
// public shape of this module is frozen and the Qt bridge can already
// bind to it.

use tokio::sync::mpsc;

/// Snapshot of the server's runtime state, sent to the Qt bridge.
#[derive(Clone, Debug)]
pub struct ServerSnapshot {
    pub running: bool,
    pub alias: String,
    pub port: u16,
    pub https: bool,
}

impl Default for ServerSnapshot {
    fn default() -> Self {
        Self {
            running: false,
            alias: String::new(),
            port: 53317,
            https: true,
        }
    }
}

/// Commands flowing Qt bridge -> server task.
#[derive(Debug)]
pub enum ServerCommand {
    Start {
        alias: String,
        port: u16,
        https: bool,
    },
    Stop,
    Restart {
        alias: String,
        port: u16,
        https: bool,
    },
    Shutdown,
}

/// Events flowing server task -> Qt bridge.
#[derive(Debug)]
pub enum ServerEvent {
    Snapshot(ServerSnapshot),
    Error(String),
}

/// Handle held by the Qt-side controller.
///
/// Spawns a Tokio task that owns the server. The task does not yet call
/// into `localsend`; that wiring is a TODO documented below.
pub struct ServerHandle {
    cmd_tx: mpsc::UnboundedSender<ServerCommand>,
}

impl ServerHandle {
    pub fn spawn<F>(mut on_event: F) -> Self
    where
        F: FnMut(ServerEvent) + Send + 'static,
    {
        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<ServerCommand>();

        // Dedicated thread + runtime: keeps the Qt thread completely
        // clear of network work.
        std::thread::Builder::new()
            .name("localsend-server".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        on_event(ServerEvent::Error(format!(
                            "failed to start server runtime: {e}"
                        )));
                        return;
                    }
                };

                rt.block_on(async move {
                    let mut snapshot = ServerSnapshot::default();
                    on_event(ServerEvent::Snapshot(snapshot.clone()));

                    while let Some(cmd) = cmd_rx.recv().await {
                        match cmd {
                            ServerCommand::Start { alias, port, https } => {
                                // TODO: connect to existing LocalSend core API.
                                //
                                // Expected call (from app/lib/provider/network/server/server_provider.dart):
                                //   localsend::http::server::start_server(...)
                                //       alias, port, https, pin, verify_checksums,
                                //       web params, show_token
                                //   returns a stream of server events
                                //   (Started, Register, PrepareUpload, FileUpload,
                                //    FileUploadProgress, FileUploadResult, SessionEnd,
                                //    PrepareUploadAborted, CancelReceived, Show,
                                //    WebPrepareDownload, WebFileDownload,
                                //    ListenerFailed)
                                //
                                // We will forward each event as ServerEvent::… once
                                // the exact API is known. Do NOT guess signatures here.
                                snapshot = ServerSnapshot {
                                    running: false, // real value once wired
                                    alias,
                                    port,
                                    https,
                                };
                                on_event(ServerEvent::Snapshot(snapshot.clone()));
                                on_event(ServerEvent::Error(
                                    "ServerService: core wiring pending (TODO)".into(),
                                ));
                            }
                            ServerCommand::Stop => {
                                // TODO: call core to stop the running server.
                                snapshot.running = false;
                                on_event(ServerEvent::Snapshot(snapshot.clone()));
                            }
                            ServerCommand::Restart { alias, port, https } => {
                                // TODO: stop then start via core.
                                snapshot = ServerSnapshot {
                                    running: false,
                                    alias,
                                    port,
                                    https,
                                };
                                on_event(ServerEvent::Snapshot(snapshot.clone()));
                            }
                            ServerCommand::Shutdown => break,
                        }
                    }
                });
            })
            .expect("failed to spawn localsend-server thread");

        Self { cmd_tx }
    }

    pub fn send(&self, cmd: ServerCommand) {
        let _ = self.cmd_tx.send(cmd);
    }
}