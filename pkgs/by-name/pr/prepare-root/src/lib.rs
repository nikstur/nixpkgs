mod config;

use std::{
    fs,
    os::unix::fs::{chroot, PermissionsExt},
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, Context, Result};
use sysinfo::Disks;

use config::Config;

const NIX_STORE_PATH: &str = "/nix/store";

/// Activate the system.
pub fn init() -> Result<()> {
    let config = Config::from_env()?;

    log::info!("Setting up Nix Store permissions...");
    setup_nix_store_permissions();

    log::info!("Re-mounting Nix Store read-only...");
    remount_nix_store_read_only()?;

    log::info!("Setting up /run/booted-system...");
    atomic_symlink(&config.toplevel, "/run/booted-system")?;

    log::info!("Setting up modprobe...");
    setup_modprobe(&config.modprobe_binary)?;

    log::info!("Activating the system...");
    activate(&config)?;

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

/// Activate the system.
///
/// This runs both during boot and durign re-activation during switch-to-configuration.
fn activate(config: &Config) -> Result<()> {
    log::info!("Setting up /bin/sh...");
    atomic_symlink(&config.sh_binary, "/bin/sh")?;

    log::info!("Setting up /run/current-system...");
    atomic_symlink(&config.toplevel, "/run/current-system")?;

    log::info!("Setting up firmware search paths...");
    setup_firmware_search_path(&config.firmware)?;

    Ok(())
}

/// Setup modprobe so that the kernel can find the wrapped binary.
///
/// See <https://docs.kernel.org/admin-guide/sysctl/kernel.html#modprobe>
fn setup_modprobe(modprobe_binary: impl AsRef<Path>) -> Result<()> {
    const MODPROBE_PATH: &str = "/proc/sys/kernel/modprobe";

    fs::write(
        MODPROBE_PATH,
        modprobe_binary.as_ref().as_os_str().as_encoded_bytes(),
    )
    .with_context(|| {
        format!(
            "Failed to populate modprobe path with {:?}",
            modprobe_binary.as_ref()
        )
    })?;
    Ok(())
}

/// Setup the firmware search path so that the kernel can find the firmware.
///
/// See <https://www.kernel.org/doc/html/latest/driver-api/firmware/fw_search_path.html>
fn setup_firmware_search_path(firmware: impl AsRef<Path>) -> Result<()> {
    const FIRMWARE_SERCH_PATH: &str = "/sys/module/firmware_class/parameters/path";

    if Path::new(FIRMWARE_SERCH_PATH).exists() {
        fs::write(
            FIRMWARE_SERCH_PATH,
            firmware.as_ref().as_os_str().as_encoded_bytes(),
        )
        .with_context(|| {
            format!(
                "Failed to populate firmware search path with {:?}",
                firmware.as_ref()
            )
        })?;
    }

    Ok(())
}

/// Atomicaly symlink a file.
///
/// This will first symlink the original to a temporary path with a `.tmp` suffix and then move the
/// symlink to it's actual path.
fn atomic_symlink(original: impl AsRef<Path>, link: impl AsRef<Path>) -> Result<()> {
    let mut i = 0;

    let tmp_path = loop {
        let mut tmp_path = original.as_ref().as_os_str().to_os_string();
        tmp_path.push(format!(".tmp{i}"));

        let res = std::os::unix::fs::symlink(&original, &tmp_path);
        match res {
            Ok(()) => break tmp_path,
            Err(err) => {
                if err.kind() != std::io::ErrorKind::AlreadyExists {
                    return Err(err)
                        .context(format!("Failed to symlink to temporary file {tmp_path:?}"));
                }
            }
        }
        i += 1;
    };

    fs::rename(&tmp_path, &link)
        .with_context(|| format!("Failed to rename {tmp_path:?} to {:?}", link.as_ref()))?;

    Ok(())
}

/// Resolve a potential symlink at `path` with the given `prefix` as root directory
pub fn resolve_in_chroot(prefix: impl AsRef<Path>, path: impl AsRef<Path>) -> Result<PathBuf> {
    chroot(prefix).context("Failed to chroot into {prefix}")?;

    std::env::set_current_dir("/").context("Failed to set CWD to /")?;

    let res = std::fs::canonicalize(path).context("Failed to canonicalize {path}")?;

    Ok(res)
}

/// Returns the value of the `init` parameter of the given kernel `cmdline`.
pub fn extract_init(cmdline: &str) -> Result<PathBuf> {
    let init_params: Vec<&str> = cmdline
        .split_ascii_whitespace()
        .filter(|p| p.starts_with("init="))
        .collect();

    if init_params.len() != 1 {
        return Err(anyhow!(
            "expected exactly one init param on kernel cmdline: {cmdline}"
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
