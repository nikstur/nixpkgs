use std::process::ExitCode;

use nixos_init::init;

fn main() -> ExitCode {
    kernlog::init().expect("Failed to initialize kernel logger");

    match init() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            log::error!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
