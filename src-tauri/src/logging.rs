use std::fs;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

/// Initialize logging to file and stdout.
///
/// Log file: `<config dir>/dict.log` (e.g. ~/.config/dict/dict.log), NOT /tmp:
/// /tmp is world-readable and wiped on reboot — the one time the log matters
/// most (the machine died overnight) is exactly when a /tmp log vanishes.
/// The previous run's log is rotated to dict.log.1 instead of truncated, so a
/// crash report can always be paired with the run that produced it.
pub fn init() {
    let log_path = crate::settings::config_directory().join("dict.log");
    let _ = fs::create_dir_all(crate::settings::config_directory());

    // Rotate: keep exactly one previous generation for post-mortems.
    let _ = fs::rename(&log_path, log_path.with_extension("log.1"));

    let file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .expect("Failed to open log file");

    // Owner-only: log lines include device names, hotkey config, and (at debug
    // level only) transcript content.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = file.set_permissions(fs::Permissions::from_mode(0o600));
    }

    let file_layer = fmt::layer()
        .with_writer(file)
        .with_ansi(false)
        .with_target(false);

    let stdout_layer = fmt::layer()
        .with_target(false)
        .with_ansi(true);

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::registry()
        .with(filter)
        .with(file_layer)
        .with(stdout_layer)
        .init();
}
