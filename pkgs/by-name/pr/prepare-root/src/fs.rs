use std::{fs, path::Path};

use anyhow::{Context, Result};

/// Atomicaly symlink a file.
///
/// This will first symlink the original to a temporary path with a `.tmp` suffix and then move the
/// symlink to it's actual path.
pub fn atomic_symlink(original: impl AsRef<Path>, link: impl AsRef<Path>) -> Result<()> {
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
