use std::process::ExitCode;

use prepare_root::{find_prepare_root, setup_logger};
fn main() -> ExitCode {
    setup_logger();

    match find_prepare_root() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
