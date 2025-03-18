mod activate;
mod config;
mod fs;
mod init;

use std::{
    os::unix::fs::chroot,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, bail, Context, Result};

pub use crate::{activate::activate, init::init};

const NIX_STORE_PATH: &str = "/nix/store";
const SYSROOT_PATH: &str = "/sysroot";

pub fn find_etc() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;

    let init = extract_init(&cmdline)?;

    let init_in_sysroot = canonicalize_in_chroot(SYSROOT_PATH, &init)?;

    println!("init: {init_in_sysroot:?}");
    let closure = init_in_sysroot.parent().context("TODO")?;

    println!("closure: {closure:?}");

    let etc_metadata_image = Path::new(SYSROOT_PATH).join(
        canonicalize_in_chroot(SYSROOT_PATH, &closure.join("etc-metadata-image"))?
            .strip_prefix("/")?,
    );

    let etc_basedir = Path::new(SYSROOT_PATH).join(
        canonicalize_in_chroot(SYSROOT_PATH, &closure.join("etc-basedir"))?.strip_prefix("/")?,
    );

    println!("etc_metadata_image: {etc_metadata_image:?}\nbasedir: {etc_basedir:?}");

    std::os::unix::fs::symlink(etc_metadata_image, "/etc-metadata-image")
        .context("Failed to link etc metadata image")?;

    std::os::unix::fs::symlink(etc_basedir, "/etc-basedir")
        .context("Failed to link etc basedir")?;

    Ok(())
}

pub fn setup_closure_for_switch_root() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;

    let init = extract_init(&cmdline)?;

    let init_in_sysroot = canonicalize_in_chroot(SYSROOT_PATH, &init)?;
    let closure = init_in_sysroot.parent().context("TODO")?;

    // std::os::unix::fs::symlink(closure, "/nixos-closure").context("Failed to link closure")?;

    // TODO support non-systemd init binary
    std::fs::write("/run/initrd-switch-root/switch-root.env", "NEW_INIT=")
        .context("Failed to write switch-root-conf")?;

    chroot(SYSROOT_PATH).context("Failed to chroot into sysroot")?;

    std::env::set_current_dir("/").context("Failed to set CWD to /")?;

    let cmd = Command::new(closure.join("prepare-root")) // TODO fix naming 😿
        .env("TOPLEVEL", closure.as_os_str())
        .output()
        .context("Failed to run init. Most likely, the binary is not on PATH")?;

    if !cmd.status.success() {
        bail!("init exited unsuccessfully")
    }

    // TODO stderr?

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
        eprintln!("{}", String::from_utf8_lossy(&cmd.stderr));
        bail!("chroot-realpath exited unsuccessfully")
    }
    println!("{}", String::from_utf8_lossy(&cmd.stdout));

    let output =
        String::from_utf8(cmd.stdout).context("Failed to decode stdout of chroot-realpath")?;

    Ok(std::path::PathBuf::from(&output))
}

/// Resolve a potential symlink at `path` with the given `prefix` as root directory
pub fn resolve_in_chroot(prefix: impl AsRef<Path>, path: impl AsRef<Path>) -> Result<PathBuf> {
    chroot(&prefix).with_context(|| format!("Failed to chroot into {:?}", prefix.as_ref()))?;

    std::env::set_current_dir("/").context("Failed to set CWD to /")?;

    let res = std::fs::canonicalize(&path)
        .with_context(|| format!("Failed to canonicalize {:?}", path.as_ref()))?;

    Ok(res)
}
