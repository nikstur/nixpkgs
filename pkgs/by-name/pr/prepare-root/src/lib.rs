mod activate;
mod config;
mod fs;
mod init;

use std::{
    os::unix::fs::chroot,
    path::{Path, PathBuf},
};

use anyhow::{anyhow, Context, Result};

pub use crate::{activate::activate, init::init};

const NIX_STORE_PATH: &str = "/nix/store";

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
