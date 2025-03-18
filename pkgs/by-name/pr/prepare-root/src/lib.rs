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

pub fn setup_closure_for_switch_root() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;

    let init = extract_init(&cmdline)?;

    let closure = locate_system_closure("/sysroot", &init)?;

    std::os::unix::fs::symlink(closure, "/nixos-closure").context("Failed to link closure")?;

    std::fs::write("/etc/switch-root-conf", "NEW_INIT=")
        .context("Failed to write switch-root-conf")?;

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
pub fn locate_system_closure(prefix: &str, init: &Path) -> Result<PathBuf> {
    let cmd = Command::new("chroot-realpath")
        .arg(prefix)
        .arg(init.as_os_str())
        .output()
        .context("Failed to run chroot-realpath. Most likely, the binary is not on PATH")?;

    if !cmd.status.success() {
        bail!("chroot-realpath exited unsuccessfully")
    }

    let output =
        String::from_utf8(cmd.stdout).context("Failed to decode stdout of chroot-realpath")?;

    let path = std::path::Path::new(&output);

    let closure = if path.is_dir() {
        return Err(anyhow!(
            "Expected to find init, found directory instead {path:?}"
        ));
    } else {
        path.parent()
            .ok_or(anyhow!("Failed to get parent directory of {path:?}"))?
    };

    Ok(closure.to_path_buf())
}

/// Resolve a potential symlink at `path` with the given `prefix` as root directory
pub fn resolve_in_chroot(prefix: impl AsRef<Path>, path: impl AsRef<Path>) -> Result<PathBuf> {
    chroot(prefix).context("Failed to chroot into {prefix}")?;

    std::env::set_current_dir("/").context("Failed to set CWD to /")?;

    let res = std::fs::canonicalize(path).context("Failed to canonicalize {path}")?;

    Ok(res)
}
