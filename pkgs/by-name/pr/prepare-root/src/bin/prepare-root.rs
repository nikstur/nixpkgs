use std::process::ExitCode;

use prepare_root::{init, setup_logger};

fn main() -> ExitCode {
    setup_logger();

    match init() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            log::error!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
