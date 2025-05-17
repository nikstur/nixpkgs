use std::{path::Path, process::ExitCode};

use anyhow::{Context, Result};

use nixos_init::{canonicalize_in_chroot, find_init_in_sysroot, setup_logger, SYSROOT_PATH};

fn main() -> ExitCode {
    setup_logger();

    match find_etc() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}

fn find_etc() -> Result<()> {
    let init_in_sysroot = find_init_in_sysroot()?;

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
        .context("Failed to link /etc-metadata-image")?;

    std::os::unix::fs::symlink(etc_basedir, "/etc-basedir")
        .context("Failed to link /etc-basedir")?;

    Ok(())
}
