use std::process::ExitCode;

use prepare_root::find_etc;

fn main() -> ExitCode {
    match find_etc() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
