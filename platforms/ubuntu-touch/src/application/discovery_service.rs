// SPDX-License-Identifier: Apache-2.0
//
// Discovery service. Wraps `localsend::discovery::start` on a dedicated
// thread with its own Tokio runtime.
//
// It binds multicast sockets, answers announcements of peers, and accepts
// devices that were confirmed outside of discovery (e.g. peers that
// registered with our HTTP server).

use std::sync::{Arc, Mutex};
use std::sync::RwLock;
use std::thread;

use anyhow::Result;
use tokio::sync::{mpsc, oneshot};

use localsend::discovery::{
    self, DeviceChannel, DeviceIdentity as CoreDeviceIdentity, DiscoveredDevice,
    DiscoveryConfig, DiscoveryEvent as CoreDiscoveryEvent, DiscoveryHandle as CoreDiscoveryHandle,
    HttpChannel, StatefulDevice,
};
use localsend::model::discovery::{DeviceType, ProtocolType};
use localsend::multicast::{
    MulticastDevice, DEFAULT_MULTICAST_GROUP, DEFAULT_MULTICAST_GROUP_V6,
    DEFAULT_PORT as DEFAULT_MULTICAST_PORT,
};
use localsend::util::interface::InterfaceFilter;

/// Parameters needed to start discovery for this device.
#[derive(Clone, Debug)]
pub struct DiscoveryParams {
    pub alias: String,
    pub port: u16,
    pub https: bool,
    pub fingerprint: String,
    pub cert_pem: String,
    pub private_key_pem: String,
}

/// A device as exposed to the bridge.
#[derive(Clone, Debug)]
pub struct DeviceSnapshot {
    pub fingerprint: String,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<String>, // "mobile" | "desktop" | "web" | "headless" | "server"
    pub ip: String,
    pub port: u16,
    pub https: bool,
    pub download: bool,
}

/// Commands to the discovery thread.
pub enum DiscoveryCommand {
    Start(DiscoveryParams),
    /// Announce to the network + emit fresh snapshot.
    ScanNow,
    /// Add a device confirmed elsewhere (e.g. via our HTTP server).
    AddDevice(DiscoveredDevice),
    Stop,
    Shutdown,
}

/// Events from the discovery thread.
#[derive(Clone, Debug)]
pub enum DiscoveryEvent {
    DevicesChanged(Vec<DeviceSnapshot>),
    Log(String),
}

pub struct DiscoveryServiceHandle {
    cmd_tx: mpsc::UnboundedSender<DiscoveryCommand>,
    evt_rx: Mutex<Option<mpsc::UnboundedReceiver<DiscoveryEvent>>>,
    snapshot_cache: Arc<RwLock<Vec<DeviceSnapshot>>>,
}

impl DiscoveryServiceHandle {
    pub fn spawn() -> Self {
        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<DiscoveryCommand>();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel::<DiscoveryEvent>();
        let snapshot_cache = Arc::new(RwLock::new(Vec::new()));

        thread::Builder::new()
            .name("localsend-discovery".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        let _ = evt_tx
                            .send(DiscoveryEvent::Log(format!("runtime init failed: {e}")));
                        return;
                    }
                };

                rt.block_on(async move {
                    let mut running: Option<RunningDiscovery> = None;

                    while let Some(cmd) = cmd_rx.recv().await {
                        match cmd {
                            DiscoveryCommand::Start(params) => {
                                if running.is_some() {
                                    let _ = evt_tx.send(DiscoveryEvent::Log(
                                        "start requested but discovery already running".into(),
                                    ));
                                    continue;
                                }
                                match start_one(params, evt_tx.clone()).await {
                                    Ok(rd) => {
                                        let snaps = snapshot(&rd.handle);
                                        let _ =
                                            evt_tx.send(DiscoveryEvent::DevicesChanged(snaps));
                                        running = Some(rd);
                                    }
                                    Err(e) => {
                                        let _ = evt_tx.send(DiscoveryEvent::Log(format!(
                                            "discovery start failed: {e:#}"
                                        )));
                                    }
                                }
                            }
                            DiscoveryCommand::ScanNow => {
                                if let Some(rd) = &running {
                                    let _ = evt_tx.send(DiscoveryEvent::Log(
                                        "announcing to the network".into(),
                                    ));
                                    rd.handle.announce().await;
                                    let snaps = snapshot(&rd.handle);
                                    let _ = evt_tx.send(DiscoveryEvent::DevicesChanged(snaps));
                                }
                            }
                            DiscoveryCommand::AddDevice(device) => {
                                if let Some(rd) = &running {
                                    rd.handle.add_device(device).await;
                                    let snaps = snapshot(&rd.handle);
                                    let _ = evt_tx.send(DiscoveryEvent::DevicesChanged(snaps));
                                }
                            }
                            DiscoveryCommand::Stop => {
                                if let Some(rd) = running.take() {
                                    rd.stop().await;
                                    let _ = evt_tx
                                        .send(DiscoveryEvent::DevicesChanged(Vec::new()));
                                }
                            }
                            DiscoveryCommand::Shutdown => break,
                        }
                    }
                });
            })
            .expect("failed to spawn localsend-discovery thread");

        Self {
            cmd_tx,
            evt_rx: Mutex::new(Some(evt_rx)),
            snapshot_cache,
        }
    }

    pub fn send(&self, cmd: DiscoveryCommand) {
        let _ = self.cmd_tx.send(cmd);
    }

    pub fn try_recv_event(&self) -> Option<DiscoveryEvent> {
        let mut guard = self.evt_rx.lock().ok()?;
        let rx = guard.as_mut()?;
        let evt = rx.try_recv().ok()?;
        // Keep the snapshot cache fresh.
        if let DiscoveryEvent::DevicesChanged(ref snaps) = evt {
            if let Ok(mut g) = self.snapshot_cache.write() {
                *g = snaps.clone();
            }
        }
        Some(evt)
    }

    /// Latest snapshot of discovered devices, cached from the last
    /// DevicesChanged event that was drained via try_recv_event.
    pub fn snapshot(&self) -> Vec<DeviceSnapshot> {
        self.snapshot_cache
            .read()
            .map(|g| g.clone())
            .unwrap_or_default()
    }
}

struct RunningDiscovery {
    handle: Arc<CoreDiscoveryHandle>,
    stop_tx: Option<oneshot::Sender<()>>,
    forward_task: tokio::task::JoinHandle<()>,
}

impl RunningDiscovery {
    async fn stop(mut self) {
        if let Some(tx) = self.stop_tx.take() {
            let _ = tx.send(());
        }
        self.handle.wait_stopped().await;
        self.forward_task.abort();
    }
}

async fn start_one(
    params: DiscoveryParams,
    evt_tx: mpsc::UnboundedSender<DiscoveryEvent>,
) -> Result<RunningDiscovery> {
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    let (core_event_tx, mut core_event_rx) = mpsc::channel::<CoreDiscoveryEvent>(64);

    let protocol = if params.https {
        ProtocolType::Https
    } else {
        ProtocolType::Http
    };

    let config = DiscoveryConfig {
        group: DEFAULT_MULTICAST_GROUP,
        group_v6: Some(DEFAULT_MULTICAST_GROUP_V6),
        port: DEFAULT_MULTICAST_PORT,
        // TODO: wire settings.network_whitelist / network_blacklist.
        interface_filter: InterfaceFilter::default(),
        device: MulticastDevice {
            alias: params.alias.clone(),
            version: "2.2".to_string(),
            device_model: None,
            // TODO: derive from settings.device_type.
            device_type: Some(DeviceType::Desktop),
            fingerprint: params.fingerprint.clone(),
            port: params.port,
            protocol,
            download: false,
        },
        identity: CoreDeviceIdentity {
            cert_pem: params.cert_pem.clone(),
            private_key_pem: params.private_key_pem.clone(),
        },
        timeout: discovery::DEFAULT_DISCOVERY_TIMEOUT,
        event_tx: Some(core_event_tx),
    };

    let handle = Arc::new(discovery::start(config, stop_rx).await);

    if let Some(err) = handle.multicast_error() {
        let _ = evt_tx.send(DiscoveryEvent::Log(format!(
            "multicast unavailable: {err:#}"
        )));
    } else {
        let _ = evt_tx.send(DiscoveryEvent::Log("multicast bound".into()));
    }

    let handle_for_task = handle.clone();
    let forward_task = tokio::spawn(async move {
        while let Some(evt) = core_event_rx.recv().await {
            match evt {
                CoreDiscoveryEvent::Discovered { device } => {
                    let _ = evt_tx.send(DiscoveryEvent::Log(format!(
                        "discovered: {} ({})",
                        device.alias, device.fingerprint
                    )));
                    let _ = evt_tx.send(DiscoveryEvent::DevicesChanged(snapshot(
                        &handle_for_task,
                    )));
                }
                CoreDiscoveryEvent::Updated { device } => {
                    let _ = evt_tx.send(DiscoveryEvent::Log(format!(
                        "updated: {} ({})",
                        device.alias, device.fingerprint
                    )));
                    let _ = evt_tx.send(DiscoveryEvent::DevicesChanged(snapshot(
                        &handle_for_task,
                    )));
                }
                CoreDiscoveryEvent::MulticastFailed => {
                    let _ = evt_tx
                        .send(DiscoveryEvent::Log("multicast sockets failed".into()));
                }
            }
        }
    });

    Ok(RunningDiscovery {
        handle,
        stop_tx: Some(stop_tx),
        forward_task,
    })
}

fn snapshot(handle: &CoreDiscoveryHandle) -> Vec<DeviceSnapshot> {
    handle.devices().into_iter().map(stateful_to_snapshot).collect()
}

fn stateful_to_snapshot(sd: StatefulDevice) -> DeviceSnapshot {
    let device = sd.device;
    let (ip, port, https) = match device.channel.http() {
        Some(h) => (h.host.clone(), h.port, h.protocol == ProtocolType::Https),
        None => (String::new(), 0, false),
    };
    DeviceSnapshot {
        fingerprint: device.fingerprint,
        alias: device.alias,
        version: device.version,
        device_model: device.device_model,
        device_type: device.device_type.map(|dt| match dt {
            DeviceType::Mobile => "mobile".to_string(),
            DeviceType::Desktop => "desktop".to_string(),
            DeviceType::Web => "web".to_string(),
            DeviceType::Headless => "headless".to_string(),
            DeviceType::Server => "server".to_string(),
        }),
        ip,
        port,
        https,
        download: device.download,
    }
}

/// Helper used by ServerController to build a DiscoveredDevice.
pub fn build_discovered_device(
    alias: String,
    version: String,
    device_model: Option<String>,
    device_type: Option<DeviceType>,
    fingerprint: String,
    ip: String,
    port: u16,
    protocol: ProtocolType,
    download: bool,
) -> DiscoveredDevice {
    DiscoveredDevice {
        alias,
        version,
        device_model,
        device_type,
        fingerprint,
        channel: DeviceChannel::Http(HttpChannel {
            host: ip,
            port,
            protocol,
        }),
        download,
    }
}