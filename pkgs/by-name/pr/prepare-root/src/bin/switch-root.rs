use std::process::ExitCode;

use prepare_root::{setup_logger, switch_root};
fn main() -> ExitCode {
    setup_logger();

    match switch_root() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
