use anyhow::{anyhow, Context, Result};
use core::str::from_utf8;
use std::os::unix::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use prepare_root::extract_init;

fn locate_system_closure(prefix: &str, init: &Path) -> Result<PathBuf> {
    let cmd = Command::new("chroot-realpath")
        .arg(prefix)
        .arg(init.as_os_str())
        .output()
        .context("Failed to execute chroot-realpath")?;

    assert!(cmd.status.success(), "chroot-realpath failed");

    let output = from_utf8(&cmd.stdout).context("Failed to decode resolved path")?;

    let path = std::path::Path::new(output);

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

fn main() -> Result<()> {
    let cmdline = std::fs::read_to_string("/proc/cmdline")?;

    let init = extract_init(&cmdline)?;

    let closure = locate_system_closure("/sysroot", &init)?;

    fs::symlink(closure, "/nixos-closure").context("Failed to link closure")?;

    std::fs::write("/etc/switch-root-conf", "NEW_INIT=")
        .context("Failed to write switch-root-conf")?;

    Ok(())
}
