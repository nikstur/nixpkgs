use std::{
    env,
    io::{stdout, Write},
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
};

use anyhow::{anyhow, Context, Result};

use nixos_init::setup_logger;

fn main() -> Result<()> {
    setup_logger();

    let args: Vec<String> = env::args().collect();

    if args.len() != 3 {
        return Err(anyhow!("Usage: {} <chroot> <path>", args[0]));
    }

    let path = resolve_in_chroot(&args[1], &args[2])?;

    stdout().write_all(path.into_os_string().as_bytes())?;

    Ok(())
}

/// Resolve a potential symlink at `path` with the given `prefix` as root directory
fn resolve_in_chroot(prefix: impl AsRef<Path>, path: impl AsRef<Path>) -> Result<PathBuf> {
    std::os::unix::fs::chroot(&prefix)
        .with_context(|| format!("Failed to chroot into {:?}", prefix.as_ref()))?;

    std::env::set_current_dir("/").context("Failed to set CWD to /")?;

    let res = std::fs::canonicalize(&path)
        .with_context(|| format!("Failed to canonicalize {:?}", path.as_ref()))?;

    Ok(res)
}
