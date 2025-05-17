use std::{fs, path::Path};

use anyhow::{Context, Result};

use crate::{config::Config, fs::atomic_symlink};

/// Activate the system.
///
/// This runs both during boot and durign re-activation during switch-to-configuration.
pub fn activate(config: &Config) -> Result<()> {
    log::info!("Setting up /run/current-system...");
    atomic_symlink(&config.toplevel, "/run/current-system")?;

    log::info!("Setting up modprobe...");
    setup_modprobe(&config.modprobe_binary)?;

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
