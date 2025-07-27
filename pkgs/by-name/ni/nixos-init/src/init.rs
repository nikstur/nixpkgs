use std::{
    fs,
    os::unix::{fs::PermissionsExt, process::CommandExt},
    process::Command,
};

use anyhow::{Context, Result};
use sysinfo::Disks;

use crate::{activate::activate, config::Config, fs::atomic_symlink, NIX_STORE_PATH};

/// Activate the system.
pub fn init() -> Result<()> {
    let args = std::env::args_os().skip(1).collect::<Vec<_>>();
    log::debug!(
        "Received arguments: {}",
        args.iter()
            .filter_map(|s| s.as_os_str().to_str())
            .collect::<Vec<_>>()
            .join(" ")
    );

    let config = Config::from_env().context("Failed to get configuration")?;

    // This is a dumb workaround for systemd to not shit its pants when there is no populated
    // /usr.
    log::info!("Setting up /usr for systemd...");
    fs::create_dir_all("/usr/bin").context("Failed to create a populated /usr")?;

    log::info!("Setting up Nix Store permissions...");
    setup_nix_store_permissions();

    log::info!("Re-mounting Nix Store read-only...");
    remount_nix_store_read_only()?;

    log::info!("Setting up /run/booted-system...");
    atomic_symlink(&config.toplevel, "/run/booted-system")?;

    log::info!("Activating the system...");
    activate(&config)?;

    log::info!("Executing systemd...");
    let _ = Command::new(&config.systemd_binary).args(args).exec();

    Ok(())
}

/// Set up the correct permissions for the Nix Store.
///
/// Gracefully fail if they cannot be changed to accomodate read-only filesystems.
pub fn setup_nix_store_permissions() {
    const ROOT_UID: u32 = 0;
    const NIXBUILD_GID: u32 = 0;
    const NIX_STORE_MODE: u32 = 0o1775;

    std::os::unix::fs::chown(NIX_STORE_PATH, Some(ROOT_UID), Some(NIXBUILD_GID)).ok();
    fs::metadata(NIX_STORE_PATH)
        .map(|metadata| {
            let mut permissions = metadata.permissions();
            permissions.set_mode(NIX_STORE_MODE);
        })
        .ok();
}

/// Remount the Nix Store read only
pub fn remount_nix_store_read_only() -> Result<()> {
    // Find the last mounted Nix Store.
    let disks = Disks::new_with_refreshed_list();
    let disk = disks
        .list()
        .iter()
        .rev()
        .find(|d| d.mount_point().as_os_str() == NIX_STORE_PATH)
        .with_context(|| format!("Failed to find the mount point for {NIX_STORE_PATH}"))?;

    if !disk.is_read_only() {
        // Authored by Ryan. Only this &
        mount(&["--bind", NIX_STORE_PATH, NIX_STORE_PATH])?;
        mount(&["-o", "remount,ro,bind", NIX_STORE_PATH])?;
    }

    Ok(())
}

/// Calls `mount` with the provided `args`.
fn mount(args: &[&str]) -> Result<()> {
    let output = Command::new("mount")
        .args(args)
        .output()
        .context("Failed to run mount. Most likely, the binary is not on PATH")?;

    if !output.status.success() {
        return Err(anyhow::anyhow!(
            "mount executed unsuccessfully: {}",
            String::from_utf8_lossy(&output.stdout)
        ));
    };

    Ok(())
}
