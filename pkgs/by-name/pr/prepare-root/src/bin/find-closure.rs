use std::process::ExitCode;

use prepare_root::setup_closure_for_switch_root;

fn main() -> ExitCode {
    match setup_closure_for_switch_root() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
