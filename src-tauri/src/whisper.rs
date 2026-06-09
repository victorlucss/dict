use std::path::{Path, PathBuf};
use std::process::Command;

/// Find the whisper-cli binary on the system
pub fn find_whisper_binary() -> Option<PathBuf> {
    let candidates: Vec<&str> = if cfg!(target_os = "macos") {
        vec![
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
        ]
    } else if cfg!(target_os = "windows") {
        vec![
            "C:\\Program Files\\whisper-cpp\\whisper-cli.exe",
            "C:\\Program Files\\whisper-cpp\\main.exe",
        ]
    } else {
        // Linux
        vec![
            "/usr/local/bin/whisper-cli",
            "/usr/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
            "/usr/bin/whisper-cpp",
        ]
    };

    // Check known paths
    for path in &candidates {
        let p = Path::new(path);
        if p.exists() {
            return Some(p.to_path_buf());
        }
    }

    // Search PATH via `which` (Unix) or `where` (Windows)
    let search_names = ["whisper-cli", "whisper-cpp"];
    let which_cmd = if cfg!(target_os = "windows") {
        "where"
    } else {
        "which"
    };

    for name in &search_names {
        if let Ok(output) = Command::new(which_cmd).arg(name).output() {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout)
                    .trim()
                    .to_string();
                if !path.is_empty() {
                    let p = PathBuf::from(&path);
                    if p.exists() {
                        return Some(p);
                    }
                }
            }
        }
    }

    None
}

/// Transcribe a WAV file using whisper-cli
pub fn transcribe(
    audio_file: &Path,
    model_path: &str,
    language: &str,
) -> Result<String, String> {
    let whisper_path =
        find_whisper_binary().ok_or("whisper-cli not found. Install: brew install whisper-cpp")?;

    if model_path.is_empty() || !Path::new(model_path).exists() {
        return Err(format!("Whisper model not found at: {}", model_path));
    }

    // Use the available cores (capped to avoid contending with the audio/UI
    // threads), and greedy decoding (beam size 1) which is markedly faster than
    // the default beam search with negligible accuracy loss on short, clean
    // dictation.
    let threads = std::thread::available_parallelism()
        .map(|n| n.get().min(8))
        .unwrap_or(4)
        .to_string();
    let args = vec![
        "-m",
        model_path,
        "-l",
        language,
        "-t",
        threads.as_str(),
        "-bs",
        "1", // greedy beam (faster decode)
        "-bo",
        "1",
        "-nt", // no timestamps
        "-np", // no prints
        "-f",
        audio_file.to_str().unwrap_or(""),
    ];

    tracing::info!(
        "Running: {} {}",
        whisper_path.display(),
        args.join(" ")
    );

    let output = Command::new(&whisper_path)
        .args(&args)
        .output()
        .map_err(|e| format!("Failed to run whisper: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout)
        .trim()
        .to_string();
    let stderr = String::from_utf8_lossy(&output.stderr)
        .trim()
        .to_string();

    tracing::info!("Whisper exit: {}", output.status);
    if !stdout.is_empty() {
        tracing::info!("Whisper output: {}", stdout);
    }
    if !stderr.is_empty() {
        tracing::info!("Whisper stderr: {}", &stderr[..stderr.len().min(500)]);
    }

    // Clean up temp file
    let _ = std::fs::remove_file(audio_file);

    if output.status.success() && !stdout.is_empty() {
        // Filter out whisper noise like "[BLANK_AUDIO]"
        let cleaned = stdout.replace("[BLANK_AUDIO]", "").trim().to_string();
        if cleaned.is_empty() {
            Err("No speech detected".to_string())
        } else {
            Ok(cleaned)
        }
    } else {
        Err(format!(
            "Whisper returned no output (exit {})",
            output.status
        ))
    }
}
