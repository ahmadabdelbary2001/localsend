// SPDX-License-Identifier: Apache-2.0
//
// Send service. Uses `localsend::http::client::LsHttpClientV2` to
// prepare an upload session and stream each accepted file.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;

use anyhow::{anyhow, Context, Result};
use tokio::sync::{mpsc, oneshot};

use bytes::Bytes;
use futures::StreamExt;

use localsend::http::client::{HttpClientError, LsHttpClientV2};
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use localsend::model::discovery::{DeviceType, ProtocolType};
use localsend::model::transfer::{FileContent, FileDto};
use tokio_util::sync::CancellationToken;

use crate::application::identity_service::DeviceIdentity;

#[derive(Clone, Debug)]
pub struct SendTarget {
    pub fingerprint: String,
    pub host: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub alias: String,
}

#[derive(Clone, Debug)]
pub struct SendFileEntry {
    pub file_id: String,
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
}

#[derive(Debug)]
pub enum SendCommand {
    Start {
        session_id: String,
        target: SendTarget,
        files: Vec<SendFileEntry>,
        sender_alias: String,
        sender_port: u16,
        sender_https: bool,
        sender_fingerprint: String,
        pin: Option<String>,
    },
    SubmitPin {
        session_id: String,
        pin: String,
    },
    Cancel {
        session_id: String,
    },
    Shutdown,
}

#[derive(Debug)]
pub enum SendEvent {
    Prepared {
        session_id: String,
        remote_session_id: String,
        accepted: Vec<String>,
    },
    FileStarted {
        session_id: String,
        file_id: String,
    },
    FileProgress {
        session_id: String,
        file_id: String,
        progress: f64,
    },
    FileDone {
        session_id: String,
        file_id: String,
    },
    FileFailed {
        session_id: String,
        file_id: String,
        error: String,
    },
    PinRequired {
        session_id: String,
        invalid_pin: bool,
    },
    Declined {
        session_id: String,
    },
    RecipientBusy {
        session_id: String,
    },
    TooManyAttempts {
        session_id: String,
    },
    Finished {
        session_id: String,
        ok: bool,
        error: Option<String>,
    },
    Log(String),
}

pub struct SendServiceHandle {
    cmd_tx: mpsc::UnboundedSender<SendCommand>,
    evt_rx: std::sync::Mutex<Option<mpsc::UnboundedReceiver<SendEvent>>>,
}

impl SendServiceHandle {
    pub fn spawn(identity: Arc<DeviceIdentity>) -> Self {
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel();

        thread::Builder::new()
            .name("localsend-send".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        let _ = evt_tx.send(SendEvent::Log(format!("runtime init: {e}")));
                        return;
                    }
                };
                rt.block_on(send_task(identity, cmd_rx, evt_tx));
            })
            .expect("spawn send thread");

        Self {
            cmd_tx,
            evt_rx: std::sync::Mutex::new(Some(evt_rx)),
        }
    }

    pub fn send(&self, cmd: SendCommand) {
        let _ = self.cmd_tx.send(cmd);
    }

    pub fn try_recv_event(&self) -> Option<SendEvent> {
        let mut g = self.evt_rx.lock().ok()?;
        let rx = g.as_mut()?;
        rx.try_recv().ok()
    }
}

async fn send_task(
    identity: Arc<DeviceIdentity>,
    mut cmd_rx: mpsc::UnboundedReceiver<SendCommand>,
    evt_tx: mpsc::UnboundedSender<SendEvent>,
) {
    let mut active: HashMap<String, oneshot::Sender<()>> = HashMap::new();
    let mut active_pin: HashMap<String, mpsc::UnboundedSender<String>> = HashMap::new();

    while let Some(cmd) = cmd_rx.recv().await {
        match cmd {
            SendCommand::Start {
                session_id,
                target,
                files,
                sender_alias,
                sender_port,
                sender_https,
                sender_fingerprint,
                pin,
            } => {
                let (cancel_tx, cancel_rx) = oneshot::channel::<()>();
                let (pin_tx, pin_rx) = mpsc::unbounded_channel::<String>();
                active.insert(session_id.clone(), cancel_tx);
                active_pin.insert(session_id.clone(), pin_tx);

                let identity = identity.clone();
                let evt_tx = evt_tx.clone();
                let sid = session_id.clone();
                tokio::spawn(async move {
                    let r = do_send(
                        identity,
                        sid.clone(),
                        target,
                        files,
                        sender_alias,
                        sender_port,
                        sender_https,
                        sender_fingerprint,
                        pin,
                        evt_tx.clone(),
                        cancel_rx,
                    )
                    .await;
                    if let Err(e) = r {
                        let _ = evt_tx.send(SendEvent::Finished {
                            session_id: sid,
                            ok: false,
                            error: Some(format!("{e:#}")),
                        });
                    }
                });
            }
            SendCommand::Cancel { session_id } => {
                if let Some(tx) = active.remove(&session_id) {
                    let _ = tx.send(());
                }
                active_pin.remove(&session_id);
            }
            SendCommand::SubmitPin { session_id, pin } => {
                if let Some(tx) = active_pin.get(&session_id) {
                    let _ = tx.send(pin);
                }
            }
            SendCommand::Shutdown => break,
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn do_send(
    identity: Arc<DeviceIdentity>,
    session_id: String,
    target: SendTarget,
    files: Vec<SendFileEntry>,
    sender_alias: String,
    sender_port: u16,
    sender_https: bool,
    sender_fingerprint: String,
    pin: Option<String>,
    evt_tx: mpsc::UnboundedSender<SendEvent>,
    cancel_rx: oneshot::Receiver<()>,
    pin_rx: mpsc::UnboundedReceiver<String>,
) -> Result<()> {
    let client = LsHttpClientV2::try_new(
        &identity.private_key_pem,
        &identity.certificate_pem,
        Some(target.fingerprint.clone()),
        None,
    )
    .context("create client")?;

    let register = RegisterDtoV2 {
        alias: sender_alias,
        version: "2.2".to_string(),
        device_model: None,
        device_type: Some(DeviceType::Desktop),
        fingerprint: sender_fingerprint,
        port: sender_port,
        protocol: if sender_https {
            ProtocolType::Https
        } else {
            ProtocolType::Http
        },
        download: false,
    };

    let mut files_dto: HashMap<String, FileDto> = HashMap::new();
    for f in &files {
        let file_type = guess_file_type(&f.name);
        let metadata = localsend::model::transfer::FileMetadata::from_path(&f.path);
        files_dto.insert(
            f.file_id.clone(),
            FileDto {
                id: f.file_id.clone(),
                file_name: f.name.clone(),
                size: f.size,
                file_type: file_type.to_string(),
                sha256: None,
                preview: None,
                metadata,
            },
        );
    }

    let payload_template = PrepareUploadRequestDtoV2 {
        info: register,
        files: files_dto,
    };

    let cancel = CancellationToken::new();
    let cancel_for_wait = cancel.clone();
    tokio::spawn(async move {
        let _ = cancel_rx.await;
        cancel_for_wait.cancel();
    });

    let mut pin_attempt: i32 = 0;
    let mut current_pin = pin;
    let prepare_result = loop {
        pin_attempt += 1;
        let payload = payload_template.clone();
        match client
            .prepare_upload(
                target.protocol,
                &target.host,
                target.port,
                None,
                payload,
                current_pin.as_deref(),
                cancel.clone(),
            )
            .await
        {
            Ok(r) => break r,
            Err(HttpClientError::StatusCode { status, .. }) => match status {
                401 => {
                    let _ = evt_tx.send(SendEvent::PinRequired {
                        session_id: session_id.clone(),
                        invalid_pin: pin_attempt > 1,
                    });
                    tokio::select! {
                        maybe_pin = pin_rx.recv() => match maybe_pin {
                            Some(p) => { current_pin = Some(p); }
                            None => return Ok(()),
                        }
                        _cancel = cancel.cancelled() => return Ok(()),
                    }
                }
                403 => {
                    let _ = evt_tx.send(SendEvent::Declined {
                        session_id: session_id.clone(),
                    });
                    return Ok(());
                }
                409 => {
                    let _ = evt_tx.send(SendEvent::RecipientBusy {
                        session_id: session_id.clone(),
                    });
                    return Ok(());
                }
                429 => {
                    let _ = evt_tx.send(SendEvent::TooManyAttempts {
                        session_id: session_id.clone(),
                    });
                    return Ok(());
                }
                _ => return Err(anyhow!("HTTP {status}")),
            },
            Err(e) => return Err(e.into()),
        }
    };

    let (remote_session_id, accepted_files) = match prepare_result.response {
        Some(r) => (r.session_id, r.files),
        None => {
            let _ = evt_tx.send(SendEvent::Finished {
                session_id,
                ok: true,
                error: None,
            });
            return Ok(());
        }
    };

    let _ = evt_tx.send(SendEvent::Prepared {
        session_id: session_id.clone(),
        remote_session_id: remote_session_id.clone(),
        accepted: accepted_files.keys().cloned().collect(),
    });

    let mut failed_count: usize = 0;
    let mut rejected_count: usize = 0;

    for f in files {
        let Some(token) = accepted_files.get(&f.file_id) else {
            rejected_count += 1;
            let _ = evt_tx.send(SendEvent::FileFailed {
                session_id: session_id.clone(),
                file_id: f.file_id.clone(),
                error: "rejected by receiver".into(),
            });
            continue;
        };
        let _ = evt_tx.send(SendEvent::FileStarted {
            session_id: session_id.clone(),
            file_id: f.file_id.clone(),
        });

        let progress_tx = evt_tx.clone();
        let sid = session_id.clone();
        let fid = f.file_id.clone();
        let file_size = f.size;

        let content = FileContent::Path(f.path.clone());

        let mut sent: u64 = 0;
        let stream = content.into_stream().map(move |chunk| {
            let chunk = chunk?;
            sent += chunk.len() as u64;
            let p = if file_size == 0 {
                1.0
            } else {
                (sent as f64 / file_size as f64).min(1.0)
            };
            let _ = progress_tx.send(SendEvent::FileProgress {
                session_id: sid.clone(),
                file_id: fid.clone(),
                progress: p,
            });
            Ok::<Bytes, anyhow::Error>(chunk)
        });
        let body = localsend::reqwest::Body::wrap_stream(stream);

        let result = client
            .upload(
                target.protocol,
                &target.host,
                target.port,
                None,
                &remote_session_id,
                &f.file_id,
                token,
                body,
                cancel.clone(),
            )
            .await;

        match result {
            Ok(()) => {
                let _ = evt_tx.send(SendEvent::FileDone {
                    session_id: session_id.clone(),
                    file_id: f.file_id.clone(),
                });
            }
            Err(e) => {
                failed_count += 1;
                let _ = evt_tx.send(SendEvent::FileFailed {
                    session_id: session_id.clone(),
                    file_id: f.file_id.clone(),
                    error: format!("{e:#}"),
                });
            }
        }
    }

    // C05: session success is derived from per-file outcomes, never hardcoded.
    let ok = failed_count == 0 && rejected_count == 0;
    let error = if failed_count > 0 {
        Some(format!("{failed_count} file(s) failed to upload"))
    } else if rejected_count > 0 {
        Some(format!("{rejected_count} file(s) rejected by receiver"))
    } else {
        None
    };

    let _ = evt_tx.send(SendEvent::Finished {
        session_id,
        ok,
        error,
    });
    Ok(())
}

/// Map a filename extension to the LocalSend protocol `file_type` string.
/// Values match what the Dart side sends (see FileType enum in Dart).
fn guess_file_type(name: &str) -> &'static str {
    let ext = std::path::Path::new(name)
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "heic" | "heif" | "tiff" | "svg" => {
            "image"
        }
        "mp4" | "mov" | "mkv" | "avi" | "webm" | "m4v" | "flv" | "wmv" => "video",
        "mp3" | "wav" | "flac" | "ogg" | "m4a" | "aac" | "opus" => "audio",
        "txt" | "md" | "pdf" | "doc" | "docx" | "odt" | "rtf" | "json" | "xml" | "html" | "csv" => {
            "text"
        }
        "apk" => "apk",
        _ => "other",
    }
}
