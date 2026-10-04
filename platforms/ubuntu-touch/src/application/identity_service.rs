// SPDX-License-Identifier: Apache-2.0
//
// Persists the device's self-signed certificate + private key.
// Generated once on first launch, reloaded after that.
// Stored at ~/.config/localsend/{certificate,private_key,public_key}.pem
// and fingerprint.txt.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};

use crate::platform::filesystem;

pub struct DeviceIdentity {
    pub certificate_pem: String,
    pub private_key_pem: String,
    pub public_key_pem: String,
    pub fingerprint: String,
}

impl DeviceIdentity {
    pub fn load_or_generate() -> Result<Self> {
        let dir = filesystem::app_config_dir()
            .ok_or_else(|| anyhow!("no config dir available"))?;
        std::fs::create_dir_all(&dir)?;

        let cert_path = dir.join("certificate.pem");
        let key_path = dir.join("private_key.pem");
        let pub_path = dir.join("public_key.pem");
        let fp_path = dir.join("fingerprint.txt");

        if cert_path.exists() && key_path.exists() && fp_path.exists() {
            log::info!("DeviceIdentity: loading from {}", dir.display());
            let certificate_pem = std::fs::read_to_string(&cert_path)?;
            let private_key_pem = std::fs::read_to_string(&key_path)?;
            let public_key_pem = std::fs::read_to_string(&pub_path).unwrap_or_default();
            let fingerprint = std::fs::read_to_string(&fp_path)?.trim().to_string();
            return Ok(Self {
                certificate_pem,
                private_key_pem,
                public_key_pem,
                fingerprint,
            });
        }

        log::info!("DeviceIdentity: generating new certificate (RSA-2048)…");
        let generated = localsend::crypto::cert::generate_self_signed()
            .context("generate_self_signed failed")?;

        std::fs::write(&cert_path, &generated.certificate_pem)?;
        std::fs::write(&key_path, &generated.private_key_pem)?;
        std::fs::write(&pub_path, &generated.public_key_pem)?;
        std::fs::write(&fp_path, &generated.fingerprint)?;

        Ok(Self {
            certificate_pem: generated.certificate_pem,
            private_key_pem: generated.private_key_pem,
            public_key_pem: generated.public_key_pem,
            fingerprint: generated.fingerprint,
        })
    }
}