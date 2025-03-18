use std::process::ExitCode;

use prepare_root::{find_etc, setup_logger};

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
