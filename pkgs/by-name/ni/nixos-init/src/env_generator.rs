use std::{fs, io::Write};

use anyhow::Result;

const SYSTEMD_GENERATORS_PATH_LOCATION: &str = "/etc/systemd-generators-path";
const KMSG_PATH: &str = "/dev/kmsg";

/// Implementation for the entrypoint of the `env-generator` binary.
///
/// Reads the PATH for systemd generators from /etc/systemd-generators-path and prints it to
/// stdout. This makes the PATH available for all the other systemd generators.
///
/// Generators cannot use normal logging but have to write to /dev/kmsg.
fn env_generator_impl() {
    let Ok(path_content) = fs::read_to_string(SYSTEMD_GENERATORS_PATH_LOCATION) else {
        // Sometimes we do not have /dev/kmsg, e.g. inside a container
        if let Ok(mut kmsg) = fs::OpenOptions::new().write(true).open(KMSG_PATH) {
            let kmsg_msg =
                format!("<3>env-generator: Failed to read {SYSTEMD_GENERATORS_PATH_LOCATION}");
            let _ = kmsg.write(kmsg_msg.as_bytes());
        }
        return;
    };
    println!("PATH={}", path_content.trim_end_matches('\n'));
}

/// Entrypoint for the `env-generator` binary.
///
/// The return value is just here so that we can use the `main.rs` entrypoint for this binary.
/// Errors returned from this function will not be logged and thus are meaningless.
pub fn env_generator() -> Result<()> {
    env_generator_impl();
    Ok(())
}
