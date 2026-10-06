// SPDX-License-Identifier: Apache-2.0
//
// Real server service. Wires directly to `localsend::http::server`.
//
// Incoming transfers:
//   1. Core emits ServerEventV2::PrepareUpload with a oneshot decision_tx.
//   2. We store decision_tx + a summary of the request in `pending_decisions`
//      / `incoming`, and forward a simplified ServerEvent::PrepareUpload
//      to the Qt side.
//   3. UI (QML) calls ServerCommand::AcceptUpload / DeclineUpload.
//   4. We answer via decision_tx; core then emits FileUpload events with a
//      oneshot target_tx per file.
//   5. For each FileUpload, we compute a unique save path in
//      ~/.local/share/localsend/received/ and send FileUploadTarget::Path
//      via target_tx. Progress events arrive on progress_rx, the final
//      result on result_rx; both are forwarded to the Qt side.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;

use anyhow::{Context, Result};
use tokio::sync::{mpsc, oneshot};

use localsend::http::dto_v2::RegisterDtoV2;
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use localsend::http::server::web::{WebConfig, WebI18n, WebMode, WebPages};
use localsend::http::server::{
    start_with_port, ServerConfigV2, ServerHandle as CoreServerHandle, TlsConfig,
};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;

use crate::application::identity_service::DeviceIdentity;
use crate::platform::filesystem;

// -------------------- snapshots & DTOs exposed to the bridge --------------------

#[derive(Clone, Debug, Default)]
pub struct ServerSnapshot {
    pub running: bool,
    pub alias: String,
    pub port: u16,
    pub https: bool,
    pub local_ips: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct IncomingFile {
    pub file_id: String,
    pub file_name: String,
    pub size: u64,
}

#[derive(Clone, Debug)]
pub struct IncomingSession {
    pub session_id: String,
    pub sender_alias: String,
    pub sender_fingerprint: String,
    pub sender_ip: String,
    pub files: Vec<IncomingFile>,
}

// -------------------- commands & events --------------------

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
    AcceptUpload {
        session_id: String,
    },
    DeclineUpload {
        session_id: String,
    },
    /// For headless testing: auto-accept every incoming upload.
    SetAutoAccept(bool),
    Shutdown,
}

#[derive(Debug)]
pub enum ServerEvent {
    Snapshot(ServerSnapshot),
    Register {
        ip: String,
        info: RegisterDtoV2,
    },
    PrepareUpload(IncomingSession),
    PrepareUploadAborted {
        session_id: String,
    },
    FileUploadStarted {
        session_id: String,
        file_id: String,
    },
    FileUploadProgress {
        session_id: String,
        file_id: String,
        progress: f64,
    },
    FileUploadResult {
        session_id: String,
        file_id: String,
        path: Option<String>,
        error: Option<String>,
    },
    SessionEnd {
        session_id: String,
        cancelled: bool,
    },
    Log(String),
}

// -------------------- handle --------------------

pub struct ServerHandle {
    cmd_tx: mpsc::UnboundedSender<ServerCommand>,
    evt_rx: Mutex<Option<mpsc::UnboundedReceiver<ServerEvent>>>,
}

impl ServerHandle {
    pub fn spawn(identity: Arc<DeviceIdentity>) -> Self {
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel::<ServerCommand>();
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
                rt.block_on(server_task(identity, cmd_rx, evt_tx));
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

    pub fn try_recv_event(&self) -> Option<ServerEvent> {
        let mut guard = self.evt_rx.lock().ok()?;
        let rx = guard.as_mut()?;
        rx.try_recv().ok()
    }
}

// -------------------- task --------------------

async fn server_task(
    identity: Arc<DeviceIdentity>,
    mut cmd_rx: mpsc::UnboundedReceiver<ServerCommand>,
    evt_tx: mpsc::UnboundedSender<ServerEvent>,
) {
    let mut running: Option<RunningServer> = None;
    let mut pending_decisions: HashMap<String, oneshot::Sender<PrepareUploadDecisionV2>> =
        HashMap::new();
    let mut incoming: HashMap<String, IncomingSession> = HashMap::new();
    let mut auto_accept = false;

    let (core_tx, mut core_rx) = mpsc::unbounded_channel::<ServerEventV2>();

    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                let Some(cmd) = cmd else { break; };
                match cmd {
                    ServerCommand::Start { alias, port, https, pin, verify_checksums } => {
                        if running.is_some() {
                            let _ = evt_tx.send(ServerEvent::Log("already running".into()));
                            continue;
                        }
                        match start_one(
                            &identity, &alias, port, https, pin, verify_checksums,
                            core_tx.clone(), evt_tx.clone(),
                        ).await {
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
                                let _ = evt_tx.send(ServerEvent::Log(format!("start failed: {e:#}")));
                                let _ = evt_tx.send(ServerEvent::Snapshot(ServerSnapshot::default()));
                            }
                        }
                    }
                    ServerCommand::Stop => {
                        if let Some(server) = running.take() {
                            server.stop().await;
                            let _ = evt_tx.send(ServerEvent::Snapshot(ServerSnapshot::default()));
                        }
                        pending_decisions.clear();
                        incoming.clear();
                    }
                    ServerCommand::AcceptUpload { session_id } => {
                        if let Some(tx) = pending_decisions.remove(&session_id) {
                            let file_ids: HashSet<String> = incoming
                                .get(&session_id)
                                .map(|s| s.files.iter().map(|f| f.file_id.clone()).collect())
                                .unwrap_or_default();
                            let _ = tx.send(PrepareUploadDecisionV2::Accept(file_ids));
                            let _ = evt_tx.send(ServerEvent::Log(format!(
                                "accepted session {session_id}"
                            )));
                        }
                    }
                    ServerCommand::DeclineUpload { session_id } => {
                        if let Some(tx) = pending_decisions.remove(&session_id) {
                            let _ = tx.send(PrepareUploadDecisionV2::Decline);
                            let _ = evt_tx.send(ServerEvent::Log(format!(
                                "declined session {session_id}"
                            )));
                        }
                        incoming.remove(&session_id);
                    }
                    ServerCommand::SetAutoAccept(v) => {
                        auto_accept = v;
                        if v {
                            let ids: Vec<String> = pending_decisions.keys().cloned().collect();
                            for session_id in ids {
                                if let Some(tx) = pending_decisions.remove(&session_id) {
                                    let file_ids: HashSet<String> = incoming
                                        .get(&session_id)
                                        .map(|s| s.files.iter().map(|f| f.file_id.clone()).collect())
                                        .unwrap_or_default();
                                    let _ = tx.send(PrepareUploadDecisionV2::Accept(file_ids));
                                    let _ = evt_tx.send(ServerEvent::Log(format!(
                                        "auto-accepted {session_id}"
                                    )));
                                }
                            }
                        }
                    }
                    ServerCommand::Shutdown => break,
                }
            }

            evt = core_rx.recv() => {
                let Some(evt) = evt else { continue; };
                handle_core_event(
                    evt,
                    &evt_tx,
                    &mut pending_decisions,
                    &mut incoming,
                    auto_accept,
                );
            }
        }
    }

    if let Some(server) = running.take() {
        server.stop().await;
    }
}

fn handle_core_event(
    evt: ServerEventV2,
    evt_tx: &mpsc::UnboundedSender<ServerEvent>,
    pending_decisions: &mut HashMap<String, oneshot::Sender<PrepareUploadDecisionV2>>,
    incoming: &mut HashMap<String, IncomingSession>,
    auto_accept: bool,
) {
    match evt {
        ServerEventV2::Register { ip, info } => {
            let _ = evt_tx.send(ServerEvent::Register {
                ip: ip.to_string(),
                info,
            });
        }
        ServerEventV2::PrepareUpload {
            session_id,
            ip,
            info,
            cert_fingerprint,
            files,
            decision_tx,
        } => {
            let sender_fingerprint = cert_fingerprint.unwrap_or_else(|| info.fingerprint.clone());
            let mut file_list: Vec<IncomingFile> = files
                .iter()
                .map(|(id, f)| IncomingFile {
                    file_id: id.clone(),
                    file_name: f.file_name.clone(),
                    size: f.size,
                })
                .collect();
            file_list.sort_by(|a, b| a.file_name.cmp(&b.file_name));

            let session = IncomingSession {
                session_id: session_id.clone(),
                sender_alias: info.alias.clone(),
                sender_fingerprint,
                sender_ip: ip.to_string(),
                files: file_list.clone(),
            };

            // If auto-accept is on, answer immediately; otherwise store the
            // decision_tx for the bridge to answer.
            if auto_accept {
                let file_ids: HashSet<String> =
                    file_list.iter().map(|f| f.file_id.clone()).collect();
                let _ = decision_tx.send(PrepareUploadDecisionV2::Accept(file_ids));
                let _ = evt_tx.send(ServerEvent::Log(format!(
                    "auto-accepted session {session_id}"
                )));
            } else {
                pending_decisions.insert(session_id.clone(), decision_tx);
            }

            let _ = evt_tx.send(ServerEvent::PrepareUpload(session.clone()));
            incoming.insert(session_id.clone(), session);
        }
        ServerEventV2::FileUpload {
            session_id,
            file_id,
            file,
            target_tx,
        } => {
            let dest = destination_dir();
            let safe_name = sanitize_file_name(&file.file_name);
            let save_path = unique_path(&dest, &safe_name);
            if let Some(parent) = save_path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }

            let (result_tx, result_rx) = oneshot::channel::<Result<(), String>>();
            let (progress_tx, mut progress_rx) = mpsc::channel::<u64>(16);
            let target = FileUploadTarget::Path {
                path: save_path.clone(),
                result_tx,
                progress_tx: Some(progress_tx),
            };

            if target_tx.send(target).is_err() {
                let _ = evt_tx.send(ServerEvent::Log(format!(
                    "target_tx closed for {file_id}"
                )));
                return;
            }

            let _ = evt_tx.send(ServerEvent::FileUploadStarted {
                session_id: session_id.clone(),
                file_id: file_id.clone(),
            });

            // Forward progress.
            let evt_tx_p = evt_tx.clone();
            let sid = session_id.clone();
            let fid = file_id.clone();
            let size = file.size;
            tokio::spawn(async move {
                while let Some(written) = progress_rx.recv().await {
                    let progress = if size == 0 {
                        1.0
                    } else {
                        (written as f64 / size as f64).min(1.0)
                    };
                    let _ = evt_tx_p.send(ServerEvent::FileUploadProgress {
                        session_id: sid.clone(),
                        file_id: fid.clone(),
                        progress,
                    });
                }
            });

            // Forward result.
            let evt_tx_r = evt_tx.clone();
            let path_str = save_path.to_string_lossy().to_string();
            tokio::spawn(async move {
                match result_rx.await {
                    Ok(Ok(())) => {
                        let _ = evt_tx_r.send(ServerEvent::FileUploadResult {
                            session_id,
                            file_id,
                            path: Some(path_str),
                            error: None,
                        });
                    }
                    Ok(Err(e)) => {
                        let _ = evt_tx_r.send(ServerEvent::FileUploadResult {
                            session_id,
                            file_id,
                            path: None,
                            error: Some(e),
                        });
                    }
                    Err(_) => {
                        let _ = evt_tx_r.send(ServerEvent::FileUploadResult {
                            session_id,
                            file_id,
                            path: None,
                            error: Some("upload task cancelled".into()),
                        });
                    }
                }
            });
        }
        ServerEventV2::SessionEnd { session_id, reason } => {
            let cancelled = !matches!(
                reason,
                localsend::http::server::v2::SessionEndReasonV2::Finished
            );
            incoming.remove(&session_id);
            let _ = evt_tx.send(ServerEvent::SessionEnd {
                session_id,
                cancelled,
            });
        }
        ServerEventV2::PrepareUploadAborted { session_id } => {
            pending_decisions.remove(&session_id);
            incoming.remove(&session_id);
            let _ = evt_tx.send(ServerEvent::PrepareUploadAborted { session_id });
        }
        ServerEventV2::CancelReceived { ip, session_id } => {
            let _ = evt_tx.send(ServerEvent::Log(format!(
                "cancel-received from {ip} for {session_id}"
            )));
        }
        ServerEventV2::ListenerFailed { error } => {
            let _ = evt_tx.send(ServerEvent::Log(format!("LISTENER FAILED: {error}")));
        }
    }
}

// -------------------- running server --------------------

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
    alias: &str,
    port: u16,
    https: bool,
    pin: Option<String>,
    verify_checksums: bool,
    core_tx: mpsc::UnboundedSender<ServerEventV2>,
    _evt_tx: mpsc::UnboundedSender<ServerEvent>,
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
        alias: alias.to_string(),
        version: "2.2".to_string(),
        device_model: None,
        device_type: Some(DeviceType::Mobile),
        token: identity.fingerprint.clone(),
    };

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
        None,
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

    // Forward core events to our own task (which owns the decision/target maps).
    let forward_task = tokio::spawn(async move {
        while let Some(evt) = core_event_rx.recv().await {
            if core_tx.send(evt).is_err() {
                break;
            }
        }
    });

    Ok(RunningServer {
        handle,
        stop_tx: Some(stop_tx),
        forward_task,
    })
}

// -------------------- filesystem helpers --------------------

fn destination_dir() -> PathBuf {
    let base = filesystem::app_data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp/localsend-received"));
    let dir = base.join("received");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn sanitize_file_name(name: &str) -> String {
    // Take the last component of either separator; reject traversal.
    let base = name.rsplit(['/', '\\']).next().unwrap_or(name);
    let base = base.trim();
    if base.is_empty() || base == "." || base == ".." {
        return "file".to_string();
    }
    base.to_string()
}

fn unique_path(dir: &Path, name: &str) -> PathBuf {
    let mut candidate = dir.join(name);
    if !candidate.exists() {
        return candidate;
    }
    let path = Path::new(name);
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(name);
    let ext = path.extension().and_then(|s| s.to_str());
    let mut n = 1u32;
    loop {
        let new_name = match ext {
            Some(e) => format!("{stem} ({n}).{e}"),
            None => format!("{stem} ({n})"),
        };
        candidate = dir.join(&new_name);
        if !candidate.exists() {
            return candidate;
        }
        n += 1;
    }
}