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
//   5. For each FileUpload, we compute a unique save path with
//      `filesystem::resolve_receive_dir` (the configured destination, then
//      `~/Downloads/LocalSend`, then the app-private received folder) and send
//      FileUploadTarget::Path via target_tx. Progress events arrive on
//      progress_rx, the final result on result_rx; both are forwarded to the
//      Qt side.

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
    ServerConfigV2, ServerHandle as CoreServerHandle, TlsConfig, start_with_port,
};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;

use crate::application::favorites_service::FavoritesService;
use crate::application::identity_service::DeviceIdentity;
use crate::bridge::translator::translate;
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

#[derive(Clone, Debug, PartialEq)]
pub struct IncomingFileEntry {
    pub file_id: String,
    pub file_name: String,
    pub size: u64,
    pub progress: f64,  // 0.0 .. 1.0
    pub status: String, // "queue" | "sending" | "finished" | "failed"
    pub path: Option<String>,
    pub error: Option<String>,
}

// -------------------- commands & events --------------------

/// How incoming upload requests are answered without asking the user.
#[derive(Clone, Debug, PartialEq)]
pub enum AutoAcceptMode {
    /// Ask the user (default).
    Off,
    /// Accept everything (quick save).
    All,
    /// Accept only devices in the favorites list.
    Favorites,
}

#[derive(Debug)]
pub enum ServerCommand {
    Start {
        alias: String,
        port: u16,
        https: bool,
        pin: Option<String>,
        verify_checksums: bool,
        destination: Option<String>,
        locale: String,
    },
    Stop,
    AcceptUpload {
        session_id: String,
    },
    DeclineUpload {
        session_id: String,
    },
    /// Restart server with web-upload mode enabled (receive via link).
    StartWebReceive {
        alias: String,
        port: u16,
        https: bool,
        pin: Option<String>,
        verify_checksums: bool,
        destination: Option<String>,
        locale: String,
    },
    /// Set pin for active web-receive session.
    SetWebPin(Option<String>),
    /// Auto-accept policy (quick save / quick save favorites / web receive).
    SetAutoAcceptMode(AutoAcceptMode),
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
    /// Emitted when web-receive becomes active/inactive.
    WebReceiveChanged {
        active: bool,
        port: u16,
    },
}

// -------------------- handle --------------------

pub struct ServerHandle {
    cmd_tx: mpsc::UnboundedSender<ServerCommand>,
    evt_rx: Mutex<Option<mpsc::UnboundedReceiver<ServerEvent>>>,
}

impl ServerHandle {
    pub fn spawn(identity: Arc<DeviceIdentity>, favorites: Arc<FavoritesService>) -> Self {
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
                rt.block_on(server_task(identity, favorites, cmd_rx, evt_tx));
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
    favorites: Arc<FavoritesService>,
    mut cmd_rx: mpsc::UnboundedReceiver<ServerCommand>,
    evt_tx: mpsc::UnboundedSender<ServerEvent>,
) {
    let mut running: Option<RunningServer> = None;
    let mut pending_decisions: HashMap<String, oneshot::Sender<PrepareUploadDecisionV2>> =
        HashMap::new();
    let mut incoming: HashMap<String, IncomingSession> = HashMap::new();
    let mut auto_accept = AutoAcceptMode::Off;
    let mut destination: Option<PathBuf> = None;

    let (core_tx, mut core_rx) = mpsc::unbounded_channel::<ServerEventV2>();

    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                let Some(cmd) = cmd else { break; };
                match cmd {
                    ServerCommand::Start { alias, port, https, pin, verify_checksums, destination: dest, locale } => {
                        if running.is_some() {
                            let _ = evt_tx.send(ServerEvent::Log("already running".into()));
                            continue;
                        }
                        destination = dest.map(PathBuf::from).filter(|p| !p.as_os_str().is_empty());
                        match start_one(
                            &identity, &alias, port, https, pin, verify_checksums,
                            WebMode::Disabled, &locale,
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
                            let _ = evt_tx.send(ServerEvent::WebReceiveChanged { active: false, port: 0 });
                        }
                        pending_decisions.clear();
                        incoming.clear();
                    }
                    ServerCommand::StartWebReceive { alias, port, https, pin, verify_checksums, destination: dest, locale } => {
                        // Stop any running server first.
                        if let Some(server) = running.take() {
                            server.stop().await;
                        }
                        pending_decisions.clear();
                        incoming.clear();
                        destination = dest.map(PathBuf::from).filter(|p| !p.as_os_str().is_empty());
                        match start_one(
                            &identity, &alias, port, https, pin, verify_checksums,
                            WebMode::Upload, &locale,
                            core_tx.clone(), evt_tx.clone(),
                        ).await {
                            Ok(server) => {
                                let actual_port = server.handle.port();
                                let local_ips: Vec<String> = server
                                    .handle
                                    .local_addresses()
                                    .into_iter()
                                    .map(|sa| sa.ip().to_string())
                                    .collect();
                                let snap = ServerSnapshot {
                                    running: true,
                                    alias: alias.clone(),
                                    port: actual_port,
                                    https,
                                    local_ips,
                                };
                                let _ = evt_tx.send(ServerEvent::Snapshot(snap));
                                let _ = evt_tx.send(ServerEvent::WebReceiveChanged { active: true, port: actual_port });
                                running = Some(server);
                            }
                            Err(e) => {
                                let _ = evt_tx.send(ServerEvent::Log(format!("web-receive start failed: {e:#}")));
                                let _ = evt_tx.send(ServerEvent::Snapshot(ServerSnapshot::default()));
                                let _ = evt_tx.send(ServerEvent::WebReceiveChanged { active: false, port: 0 });
                            }
                        }
                    }
                    ServerCommand::SetWebPin(_new_pin) => {
                        // The pin is fixed at server start; the UI restarts the
                        // server instead of changing it in place.
                        let _ = evt_tx.send(ServerEvent::Log("SetWebPin: restart required".into()));
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
                    ServerCommand::SetAutoAcceptMode(mode) => {
                        auto_accept = mode.clone();
                        if mode != AutoAcceptMode::Off {
                            let ids: Vec<String> = pending_decisions.keys().cloned().collect();
                            for session_id in ids {
                                let allowed = match &mode {
                                    AutoAcceptMode::All => true,
                                    AutoAcceptMode::Favorites => incoming
                                        .get(&session_id)
                                        .map(|s| favorites.is_favorite(&s.sender_fingerprint))
                                        .unwrap_or(false),
                                    AutoAcceptMode::Off => false,
                                };
                                if !allowed {
                                    continue;
                                }
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
                    &auto_accept,
                    &favorites,
                    destination.as_deref(),
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
    auto_accept: &AutoAcceptMode,
    favorites: &FavoritesService,
    destination: Option<&Path>,
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

            // Quick save accepts everything, quick save for favorites only
            // accepts known devices. Otherwise the bridge answers later.
            let accept_now = match auto_accept {
                AutoAcceptMode::All => true,
                AutoAcceptMode::Favorites => favorites.is_favorite(&session.sender_fingerprint),
                AutoAcceptMode::Off => false,
            };
            if accept_now {
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
            let dest = filesystem::resolve_receive_dir(destination.and_then(|p| p.to_str()));
            let relative_name = sanitize_relative_path(&file.file_name);
            let save_path = unique_path(&dest, &relative_name);
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
                let _ = evt_tx.send(ServerEvent::Log(format!("target_tx closed for {file_id}")));
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

/// Localized strings for the browser upload page, which is rendered by the
/// Rust core rather than QML.
fn web_i18n(locale: &str) -> WebI18n {
    WebI18n {
        waiting: translate(locale, "web.waiting"),
        enter_pin: translate(locale, "web.enterPin"),
        invalid_pin: translate(locale, "web.invalidPin"),
        too_many_attempts: translate(locale, "web.tooManyAttempts"),
        rejected: translate(locale, "web.rejected"),
        upload_rejected: translate(locale, "sendPage.rejected"),
        busy: translate(locale, "sendPage.busy"),
        files: translate(locale, "web.files"),
        file_name: translate(locale, "web.fileName"),
        size: translate(locale, "web.size"),
        drop_hint: translate(locale, "sendTab.placeItems"),
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
    web_mode: WebMode,
    locale: &str,
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
        mode: web_mode,
        i18n: web_i18n(locale),
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

/// Keeps the relative directory structure of folder sends
/// (`<folder>/<relative path>`) while rejecting traversal and absolute paths.
fn sanitize_relative_path(name: &str) -> String {
    let mut parts: Vec<String> = Vec::new();
    for part in name.split(['/', '\\']) {
        let part = part.trim();
        if part.is_empty() || part == "." || part == ".." {
            continue;
        }
        // Drop a Windows drive prefix such as "C:".
        if parts.is_empty() && part.len() == 2 && part.ends_with(':') {
            continue;
        }
        parts.push(part.to_string());
    }
    if parts.is_empty() {
        return "file".to_string();
    }
    parts.join("/")
}

fn unique_path(dir: &Path, relative: &str) -> PathBuf {
    let rel = Path::new(relative);
    let parent = rel.parent().filter(|p| !p.as_os_str().is_empty());
    let file_name = rel
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_string();

    let candidate = dir.join(rel);
    if !candidate.exists() {
        return candidate;
    }

    let stem = Path::new(&file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(&file_name);
    let ext = Path::new(&file_name).extension().and_then(|s| s.to_str());
    let mut n = 1u32;
    loop {
        let new_name = match ext {
            Some(e) => format!("{stem} ({n}).{e}"),
            None => format!("{stem} ({n})"),
        };
        let candidate = match parent {
            Some(parent) => dir.join(parent).join(&new_name),
            None => dir.join(&new_name),
        };
        if !candidate.exists() {
            return candidate;
        }
        n += 1;
    }
}
