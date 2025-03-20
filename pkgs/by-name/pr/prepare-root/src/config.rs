use std::env;

use anyhow::{Context, Result};

pub struct Config {
    pub sh_binary: String,
    pub toplevel: String,
    pub firmware: String,
    pub modprobe_binary: String,
    pub systemd_binary: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let sh_binary = EnvVar::ShBinary.required()?;
        let toplevel = EnvVar::Toplevel.required()?;
        let firmware = EnvVar::Firmware.required()?;
        let modprobe_binary = EnvVar::ModprobeBinary.required()?;
        let systemd_binary = EnvVar::SystemdBinary.required()?;

        Ok(Self {
            sh_binary,
            toplevel,
            firmware,
            modprobe_binary,
            systemd_binary,
        })
    }
}

enum EnvVar {
    ShBinary,
    Toplevel,
    Firmware,
    ModprobeBinary,
    SystemdBinary,
}

impl EnvVar {
    /// Read a required environment variable.
    ///
    /// Fail with useful context if the variable is not set in the environment.
    pub fn required(&self) -> Result<String> {
        let key = self.key();
        env::var(key).with_context(|| format!("Failed to read {key} from environment"))
    }

    fn key(&self) -> &str {
        match self {
            Self::ShBinary => "SH_BINARY",
            Self::Toplevel => "TOPLEVEL",
            Self::Firmware => "FIRMWARE",
            Self::ModprobeBinary => "MODPROBE_BINARY",
            Self::SystemdBinary => "SYSTEMD_BINARY",
        }
    }
}
