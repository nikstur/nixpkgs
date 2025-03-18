use std::{io::Write, process::ExitCode};

use log::{Level, LevelFilter};

use prepare_root::init;

fn main() -> ExitCode {
    // Setup the logger to use the kernel's `printk()` scheme so that systemd can interpret the
    // levels.
    env_logger::builder()
        .format(|buf, record| {
            writeln!(
                buf,
                "<{}>{}",
                match record.level() {
                    Level::Error => 3,
                    Level::Warn => 4,
                    Level::Info => 6,
                    Level::Debug | Level::Trace => 7,
                },
                record.args()
            )
        })
        .filter(None, LevelFilter::Info)
        .init();

    match init() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            log::error!("{err:#}.");
            ExitCode::FAILURE
        }
    }
}
