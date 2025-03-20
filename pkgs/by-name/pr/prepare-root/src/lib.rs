mod activate;
mod config;
mod fs;
mod init;
mod logging;

use std::{
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, bail, Context, Result};

pub use crate::{activate::activate, init::init, logging::setup_logger};

const NIX_STORE_PATH: &str = "/nix/store";
pub const SYSROOT_PATH: &str = "/sysroot";

pub fn find_init_in_sysroot() -> Result<PathBuf> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;
    let init = extract_init(&cmdline)?;
    canonicalize_in_chroot(SYSROOT_PATH, &init)
}

/// Returns the value of the `init` parameter of the given kernel `cmdline`.
fn extract_init(cmdline: &str) -> Result<PathBuf> {
    let init_params: Vec<&str> = cmdline
        .split_ascii_whitespace()
        .filter(|p| p.starts_with("init="))
        .collect();

    if init_params.len() != 1 {
        return Err(anyhow!(
            "Expected exactly one init param on kernel cmdline: {cmdline}"
        ));
    }

    let init = init_params
        .first()
        .ok_or(anyhow!(
            "Failed to extract init parameter from kernel cmdline."
        ))?
        .split('=')
        .last()
        .ok_or(anyhow!("Failed to extract init path from init parameter."))?;

    Ok(PathBuf::from(init))
}

/// Locate the system closure.
pub fn canonicalize_in_chroot(prefix: &str, init: &Path) -> Result<PathBuf> {
    let cmd = Command::new("chroot-realpath")
        .arg(prefix)
        .arg(init.as_os_str())
        .output()
        .context("Failed to run chroot-realpath. Most likely, the binary is not on PATH")?;

    if !cmd.status.success() {
        bail!(
            "chroot-realpath exited unsuccessfully: {}",
            String::from_utf8_lossy(&cmd.stderr)
        );
    }

    let output =
        String::from_utf8(cmd.stdout).context("Failed to decode stdout of chroot-realpath")?;

    Ok(std::path::PathBuf::from(&output))
}
