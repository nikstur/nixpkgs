mod activate;
mod config;
mod fs;
mod init;
mod logging;

use std::{
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{bail, Context, Result};

pub use crate::{activate::activate, init::init, logging::setup_logger};

const NIX_STORE_PATH: &str = "/nix/store";
pub const SYSROOT_PATH: &str = "/sysroot";

/// Find the canocalized path of the init in the sysroot.
///
/// Uses the `init=` parameter on the kernel commandline.
///
/// Returns the relative path of the init to the sysroot, i.e. without the `/sysroot` prefix.
pub fn find_init_in_sysroot() -> Result<PathBuf> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;
    let init = extract_init(&cmdline)?;
    canonicalize_in_chroot(SYSROOT_PATH, &init)
}

/// Extract the value of the `init` parameter from the given kernel `cmdline`.
fn extract_init(cmdline: &str) -> Result<PathBuf> {
    let init_params: Vec<&str> = cmdline
        .split_ascii_whitespace()
        .filter(|p| p.starts_with("init="))
        .collect();

    if init_params.len() != 1 {
        bail!("Expected exactly one init param on kernel cmdline: {cmdline}")
    }

    let init = init_params
        .first()
        .and_then(|s| s.split('=').last())
        .context("Failed to extract init path from kernel cmdline: {cmdline}")?;

    Ok(PathBuf::from(init))
}

/// Canonicalize `path` in a chroot at the specified `root`.
pub fn canonicalize_in_chroot(root: &str, path: &Path) -> Result<PathBuf> {
    let output = Command::new("chroot-realpath")
        .arg(root)
        .arg(path.as_os_str())
        .output()
        .context("Failed to run chroot-realpath. Most likely, the binary is not on PATH.")?;

    if !output.status.success() {
        bail!(
            "chroot-realpath exited unsuccessfully: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let output =
        String::from_utf8(output.stdout).context("Failed to decode stdout of chroot-realpath.")?;

    Ok(PathBuf::from(&output))
}
