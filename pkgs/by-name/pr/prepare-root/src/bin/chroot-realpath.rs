use anyhow::{anyhow, Result};

use std::env;
use std::io::{stdout, Write};
use std::os::unix::ffi::OsStrExt;

use prepare_root::resolve_in_chroot;

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 3 {
        return Err(anyhow!("Usage: {} <chroot> <path>", args[0]));
    }

    let path = resolve_in_chroot(&args[1], &args[2])?;

    stdout().write_all(path.into_os_string().as_bytes())?;

    Ok(())
}
