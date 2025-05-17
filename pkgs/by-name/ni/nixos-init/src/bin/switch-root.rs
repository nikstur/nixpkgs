use std::{
    io::Write,
    process::{Command, ExitCode},
};

use anyhow::{bail, Context, Result};

use nixos_init::{find_init_in_sysroot, setup_logger, SYSROOT_PATH};

fn main() -> ExitCode {
    setup_logger();

    match switch_root() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}

/// Switches root from initrd.
fn switch_root() -> Result<()> {
    let init_in_sysroot = find_init_in_sysroot()?;

    log::info!("Switching root to {SYSROOT_PATH}...");
    log::info!("With init {init_in_sysroot:?}...");

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
