use std::io::Write;

use log::{Level, LevelFilter};

// Setup the logger to use the kernel's `printk()` scheme so that systemd can interpret the
// levels.
pub fn setup_logger() {
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
}
