mod activate;
mod config;
mod fs;
mod init;
mod logging;

use std::{
    io::Write,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, bail, Context, Result};

pub use crate::{activate::activate, init::init, logging::setup_logger};

const NIX_STORE_PATH: &str = "/nix/store";
const SYSROOT_PATH: &str = "/sysroot";

pub fn find_etc() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;
    let init = extract_init(&cmdline)?;
    let init_in_sysroot = canonicalize_in_chroot(SYSROOT_PATH, &init)?;

    let closure = init_in_sysroot
        .parent()
        .context("Provided init= is not in a directory")?;

    let etc_metadata_image = Path::new(SYSROOT_PATH).join(
        canonicalize_in_chroot(SYSROOT_PATH, &closure.join("etc-metadata-image"))?
            .strip_prefix("/")?,
    );

    let etc_basedir = Path::new(SYSROOT_PATH).join(
        canonicalize_in_chroot(SYSROOT_PATH, &closure.join("etc-basedir"))?.strip_prefix("/")?,
    );

    std::os::unix::fs::symlink(etc_metadata_image, "/etc-metadata-image")
        .context("Failed to link etc metadata image")?;

    std::os::unix::fs::symlink(etc_basedir, "/etc-basedir")
        .context("Failed to link etc basedir")?;

    Ok(())
}

/// Finds prepare-root in the toplevel, chroots and executes it.
pub fn switch_root() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;
    let init = extract_init(&cmdline)?;
    let init_in_sysroot = canonicalize_in_chroot(SYSROOT_PATH, &init)?;

    log::info!("Switching root to {SYSROOT_PATH}...");
    log::info!("Running init {init_in_sysroot:?}...");

    let cmd = Command::new("systemctl")
        .arg("--no-block")
        .arg("switch-root")
        .arg(SYSROOT_PATH)
        .arg(&init_in_sysroot)
        .output()
        .with_context(|| format!("Failed to run systemctl switch-root with {init_in_sysroot:?}"))?;

    let _ = std::io::stderr().write_all(&cmd.stderr);

    if !cmd.status.success() {
        bail!(
            "systemctl switch-root exited unsuccessfully: {}",
            String::from_utf8_lossy(&cmd.stderr)
        );
    }

    Ok(())
}

/// Returns the value of the `init` parameter of the given kernel `cmdline`.
pub fn extract_init(cmdline: &str) -> Result<PathBuf> {
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
