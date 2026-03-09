use std::fs;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

/// Initialize logging to file and stdout.
/// Log file: /tmp/dict.log (macOS/Linux), %TEMP%/dict.log (Windows)
pub fn init() {
    let log_path = log_file_path();

    // Clear log on start (match Swift behavior)
    let _ = fs::write(&log_path, "");

    let file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .expect("Failed to open log file");

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

fn log_file_path() -> String {
    if cfg!(target_os = "windows") {
        let temp = std::env::var("TEMP")
            .or_else(|_| std::env::var("TMP"))
            .unwrap_or_else(|_| ".".to_string());
        format!("{}/dict.log", temp)
    } else {
        "/tmp/dict.log".to_string()
    }
}
