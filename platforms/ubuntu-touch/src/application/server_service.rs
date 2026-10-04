// SPDX-License-Identifier: Apache-2.0
//
// Real server service. Wires directly to `localsend::http::server`.
// Runs on a dedicated thread + Tokio current-thread runtime.
//
// The public ServerHandle is held by the bridge (Qt thread).
// Commands flow Qt -> server via tokio::mpsc.
// Events flow server -> Qt via tokio::mpsc, drained by ServerController::poll().

use std::sync::{Arc, Mutex};
use std::thread;

use anyhow::{Context, Result};
use tokio::sync::{mpsc, oneshot};

use localsend::http::server::v2::{
    PrepareUploadDecisionV2, ServerEventV2,
};
use localsend::http::server::web::{WebConfig, WebI18n, WebMode, WebPages};
use localsend::http::server::{start_with_port, ServerConfigV2, ServerHandle as CoreServerHandle, TlsConfig};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;

use crate::application::identity_service::DeviceIdentity;

#[derive(Clone, Debug, Default)]
pub struct ServerSnapshot {
    pub running: bool,
    pub alias: String,
    pub port: u16,
    pub https: bool,
    pub local_ips: Vec<String>,
}

#[derive(Debug)]
pub enum ServerCommand {
    Start {
        alias: String,
        port: u16,
        https: bool,
        pin: Option<String>,
        verify_checksums: bool,
    },
    Stop,
    Shutdown,
}

#[derive(Debug, Clone)]
pub enum ServerEvent {
    Snapshot(ServerSnapshot),
    Log(String),
}

pub struct ServerHandle {
    cmd_tx: mpsc::UnboundedSender<ServerCommand>,
    evt_rx: Mutex<Option<mpsc::UnboundedReceiver<ServerEvent>>>,
}

impl ServerHandle {
    pub fn spawn(identity: Arc<DeviceIdentity>) -> Self {
        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<ServerCommand>();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel::<ServerEvent>();

        thread::Builder::new()
            .name("localsend-server".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        let _ = evt_tx.send(ServerEvent::Log(format!("runtime init failed: {e}")));
                        return;
                    }
                };

                rt.block_on(async move {
                    let mut running: Option<RunningServer> = None;

                    while let Some(cmd) = cmd_rx.recv().await {
                        match cmd {
                            ServerCommand::Start {
                                alias,
                                port,
                                https,
                                pin,
                                verify_checksums,
                            } => {
                                if running.is_some() {
                                    let _ = evt_tx.send(ServerEvent::Log(
                                        "start requested but server already running".into(),
                                    ));
                                    continue;
                                }

                                match start_one(
                                    &identity,
                                    alias.clone(),
                                    port,
                                    https,
                                    pin,
                                    verify_checksums,
                                    evt_tx.clone(),
                                )
                                .await
                                {
                                    Ok(server) => {
                                        let local_ips: Vec<String> = server
                                            .handle
                                            .local_addresses()
                                            .into_iter()
                                            .map(|sa| sa.ip().to_string())
                                            .collect();

                                        let snap = ServerSnapshot {
                                            running: true,
                                            alias: alias.clone(),
                                            port: server.handle.port(),
                                            https,
                                            local_ips,
                                        };
                                        let _ = evt_tx.send(ServerEvent::Snapshot(snap));
                                        running = Some(server);
                                    }
                                    Err(e) => {
                                        let _ = evt_tx
                                            .send(ServerEvent::Log(format!("start failed: {e:#}")));
                                        let _ = evt_tx
                                            .send(ServerEvent::Snapshot(ServerSnapshot::default()));
                                    }
                                }
                            }
                            ServerCommand::Stop => {
                                if let Some(server) = running.take() {
                                    server.stop().await;
                                    let _ = evt_tx
                                        .send(ServerEvent::Snapshot(ServerSnapshot::default()));
                                }
                            }
                            ServerCommand::Shutdown => break,
                        }
                    }
                });
            })
            .expect("failed to spawn localsend-server thread");

        Self {
            cmd_tx,
            evt_rx: Mutex::new(Some(evt_rx)),
        }
    }

    pub fn send(&self, cmd: ServerCommand) {
        let _ = self.cmd_tx.send(cmd);
    }

    /// Drain one event, if any. Called from the Qt thread.
    pub fn try_recv_event(&self) -> Option<ServerEvent> {
        let mut guard = self.evt_rx.lock().ok()?;
        let rx = guard.as_mut()?;
        rx.try_recv().ok()
    }
}

/// A running core server plus the pieces needed to stop it.
struct RunningServer {
    handle: CoreServerHandle,
    stop_tx: Option<oneshot::Sender<()>>,
    forward_task: tokio::task::JoinHandle<()>,
}

impl RunningServer {
    async fn stop(mut self) {
        if let Some(tx) = self.stop_tx.take() {
            let _ = tx.send(());
        }
        self.handle.wait_stopped().await;
        self.forward_task.abort();
    }
}

async fn start_one(
    identity: &DeviceIdentity,
    alias: String,
    port: u16,
    https: bool,
    pin: Option<String>,
    verify_checksums: bool,
    evt_tx: mpsc::UnboundedSender<ServerEvent>,
) -> Result<RunningServer> {
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    let (core_event_tx, mut core_event_rx) = mpsc::channel::<ServerEventV2>(64);

    let tls = if https {
        Some(TlsConfig {
            cert: identity.certificate_pem.clone(),
            private_key: identity.private_key_pem.clone(),
        })
    } else {
        None
    };

    let client_info = ClientInfo {
        alias: alias.clone(),
        version: "2.2".to_string(),
        device_model: None,
        device_type: Some(DeviceType::Mobile),
        token: identity.fingerprint.clone(),
    };

    // Web share disabled for now. WebI18n/WebPages are required by the
    // core API even when the mode is Disabled.
    let web_config = WebConfig {
        mode: WebMode::Disabled,
        i18n: WebI18n {
            waiting: "Waiting for response…".into(),
            enter_pin: "Enter PIN".into(),
            invalid_pin: "Invalid PIN".into(),
            too_many_attempts: "Too many attempts".into(),
            rejected: "Rejected".into(),
            upload_rejected: "Rejected".into(),
            busy: "Busy".into(),
            files: "Files".into(),
            file_name: "File name".into(),
            size: "Size".into(),
            drop_hint: "Drop files here".into(),
        },
        pages: WebPages {
            download_html: None,
            upload_html: None,
            error_403_html: None,
        },
    };

    let handle = start_with_port(
        port,
        tls,
        client_info,
        None, // internal_config (no show_token yet)
        Some(ServerConfigV2 {
            pin,
            verify_checksums,
            event_tx: core_event_tx,
        }),
        web_config,
        stop_rx,
    )
    .await
    .context("start_with_port")?;

    let forward_task = tokio::spawn(async move {
        while let Some(event) = core_event_rx.recv().await {
            match event {
                ServerEventV2::Register { ip, info } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "register: {} @ {} ({})",
                        info.alias, ip, info.fingerprint
                    )));
                }
                ServerEventV2::PrepareUpload {
                    session_id,
                    ip,
                    info,
                    files,
                    decision_tx,
                    ..
                } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "prepare-upload: {} files from {} ({}), session={}",
                        files.len(),
                        info.alias,
                        ip,
                        session_id
                    )));
                    // Skeleton: auto-decline. Real UI accept/decline will
                    // keep decision_tx alive in ServerService.
                    let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                }
                ServerEventV2::FileUpload {
                    session_id,
                    file_id,
                    target_tx,
                    ..
                } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "file-upload: session={} file={}",
                        session_id, file_id
                    )));
                    // Skeleton: dropping target_tx fails the upload.
                    drop(target_tx);
                }
                ServerEventV2::SessionEnd { session_id, reason } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "session-end: {} ({:?})",
                        session_id, reason
                    )));
                }
                ServerEventV2::PrepareUploadAborted { session_id } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "prepare-upload-aborted: {}",
                        session_id
                    )));
                }
                ServerEventV2::CancelReceived { ip, session_id } => {
                    let _ = evt_tx.send(ServerEvent::Log(format!(
                        "cancel-received from {} for {}",
                        ip, session_id
                    )));
                }
                ServerEventV2::ListenerFailed { error } => {
                    let _ = evt_tx
                        .send(ServerEvent::Log(format!("LISTENER FAILED: {}", error)));
                }
            }
        }
    });

    Ok(RunningServer {
        handle,
        stop_tx: Some(stop_tx),
        forward_task,
    })
}