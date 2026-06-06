use futures_util::StreamExt;
use serde::Serialize;
use std::path::PathBuf;
use std::time::{Duration, Instant};
use tauri::Emitter;

/// Managed models directory: `~/.config/dict/models/` on macOS/Linux,
/// `%APPDATA%/dict/models/` on Windows. Mirrors how the config dir is resolved
/// elsewhere (e.g. `open_config_file`).
pub fn models_directory() -> PathBuf {
    let config_dir = if cfg!(target_os = "windows") {
        dirs::config_dir().unwrap_or_default().join("dict")
    } else {
        dirs::home_dir()
            .unwrap_or_default()
            .join(".config")
            .join("dict")
    };
    config_dir.join("models")
}

// ─── LLM models listing ─────────────────────────────────

/// Curated fallback Anthropic model ids, used when no API key is set or the
/// live `/v1/models` fetch fails/returns nothing.
const ANTHROPIC_FALLBACK: &[&str] =
    &["claude-sonnet-4-5", "claude-opus-4-1", "claude-haiku-4-5"];

/// Curated fallback OpenAI model ids, used when no API key is set or the
/// live `/models` fetch fails/returns nothing.
const OPENAI_FALLBACK: &[&str] = &["gpt-4o", "gpt-4o-mini", "o3-mini"];

/// List available model ids for the given provider. Provider-aware: cloud
/// providers (anthropic, openai) hit their canonical endpoints with the right
/// auth and fall back to a curated static list; local providers (ollama,
/// lmstudio) derive `/models` from the configured endpoint. NEVER errors out —
/// returns a Vec (empty only on total failure for local providers).
#[tauri::command]
pub async fn list_llm_models(provider: String, endpoint: String, api_key: String) -> Vec<String> {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(4))
        .build()
    {
        Ok(c) => c,
        Err(_) => return fallback_for(&provider),
    };

    match provider.as_str() {
        "anthropic" => {
            if api_key.is_empty() {
                return dedup(ANTHROPIC_FALLBACK.iter().map(|s| s.to_string()).collect());
            }
            let req = client
                .get("https://api.anthropic.com/v1/models")
                .header("x-api-key", &api_key)
                .header("anthropic-version", "2023-06-01");
            let ids = fetch_ids(req).await;
            if ids.is_empty() {
                dedup(ANTHROPIC_FALLBACK.iter().map(|s| s.to_string()).collect())
            } else {
                ids
            }
        }
        "openai" => {
            if api_key.is_empty() {
                return dedup(OPENAI_FALLBACK.iter().map(|s| s.to_string()).collect());
            }
            let req = client
                .get("https://api.openai.com/v1/models")
                .header("Authorization", format!("Bearer {}", api_key));
            let ids = fetch_ids(req).await;
            if ids.is_empty() {
                dedup(OPENAI_FALLBACK.iter().map(|s| s.to_string()).collect())
            } else {
                ids
            }
        }
        "openrouter" => {
            // OpenRouter's /models endpoint is public (no key required).
            let mut req = client.get("https://openrouter.ai/api/v1/models");
            if !api_key.is_empty() {
                req = req.header("Authorization", format!("Bearer {}", api_key));
            }
            fetch_ids(req).await
        }
        "ollama" => {
            // Ollama's authoritative model list is its native /api/tags endpoint
            // (present on every Ollama version). Try it first, then fall back to
            // the OpenAI-compat /v1/models in case tags is unavailable.
            let tags = fetch_ids(client.get(ollama_tags_url(&endpoint))).await;
            if !tags.is_empty() {
                return tags;
            }
            fetch_ids(client.get(derive_models_url(&endpoint))).await
        }
        // "lmstudio" and any unknown provider → treat as OpenAI-compatible local.
        _ => {
            let url = derive_models_url(&endpoint);
            let mut req = client.get(&url);
            if !api_key.is_empty() {
                req = req.header("Authorization", format!("Bearer {}", api_key));
            }
            fetch_ids(req).await
        }
    }
}

/// Curated static fallback for a provider (empty for local/unknown).
fn fallback_for(provider: &str) -> Vec<String> {
    match provider {
        "anthropic" => dedup(ANTHROPIC_FALLBACK.iter().map(|s| s.to_string()).collect()),
        "openai" => dedup(OPENAI_FALLBACK.iter().map(|s| s.to_string()).collect()),
        _ => Vec::new(),
    }
}

/// Send a GET request and extract model ids from the JSON body.
/// Prefers `data[].id`, then `models[].name`, then `models[].id`.
/// Returns an EMPTY Vec on ANY error (never errors out).
async fn fetch_ids(req: reqwest::RequestBuilder) -> Vec<String> {
    let resp = match req.send().await {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let data: serde_json::Value = match resp.json().await {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };

    let mut ids: Vec<String> = Vec::new();

    // Prefer `data[].id`, else `models[].name`, else `models[].id`.
    if let Some(arr) = data["data"].as_array() {
        for item in arr {
            if let Some(id) = item["id"].as_str() {
                ids.push(id.to_string());
            }
        }
    }
    if ids.is_empty() {
        if let Some(arr) = data["models"].as_array() {
            for item in arr {
                if let Some(name) = item["name"].as_str() {
                    ids.push(name.to_string());
                }
            }
        }
    }
    if ids.is_empty() {
        if let Some(arr) = data["models"].as_array() {
            for item in arr {
                if let Some(id) = item["id"].as_str() {
                    ids.push(id.to_string());
                }
            }
        }
    }

    dedup(ids)
}

/// De-dup ids, preserving first-seen order.
fn dedup(mut ids: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    ids.retain(|id| seen.insert(id.clone()));
    ids
}

/// Derive Ollama's native `/api/tags` URL from a chat endpoint.
/// `http://localhost:11434/v1/chat/completions` → `http://localhost:11434/api/tags`.
/// Falls back to treating the whole endpoint as the base if there's no `/v1`.
fn ollama_tags_url(endpoint: &str) -> String {
    let base = match endpoint.find("/v1") {
        Some(i) => &endpoint[..i],
        None => endpoint,
    };
    format!("{}/api/tags", base.trim_end_matches('/'))
}

/// Derive the `/models` URL from a chat endpoint.
/// If `endpoint` contains `/chat/completions`, replace that with `/models`;
/// else strip a trailing `/` and append `/models`.
fn derive_models_url(endpoint: &str) -> String {
    if endpoint.contains("/chat/completions") {
        endpoint.replace("/chat/completions", "/models")
    } else {
        format!("{}/models", endpoint.trim_end_matches('/'))
    }
}

// ─── Whisper model catalog ──────────────────────────────

const HF_BASE: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

/// Curated catalog of downloadable GGML Whisper models: (name, approx size label).
const CATALOG: &[(&str, &str)] = &[
    ("tiny", "75 MB"),
    ("tiny.en", "75 MB"),
    ("base", "142 MB"),
    ("base.en", "142 MB"),
    ("small", "466 MB"),
    ("small.en", "466 MB"),
    ("medium", "1.5 GB"),
    ("medium.en", "1.5 GB"),
    ("large-v3-turbo", "1.6 GB"),
    ("large-v3", "3.1 GB"),
];

/// Minimum file size (bytes) for a model to be considered "downloaded"
/// rather than a partial/leftover file (~1 MB).
const MIN_DOWNLOADED_BYTES: u64 = 1_000_000;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WhisperModelInfo {
    pub name: String,
    pub filename: String,
    pub size: String,
    pub downloaded: bool,
    pub path: String,
}

fn filename_for(name: &str) -> String {
    format!("ggml-{}.bin", name)
}

/// List the curated Whisper model catalog with download status.
#[tauri::command]
pub fn list_whisper_models() -> Vec<WhisperModelInfo> {
    let dir = models_directory();
    CATALOG
        .iter()
        .map(|(name, size)| {
            let filename = filename_for(name);
            let path = dir.join(&filename);
            let downloaded = std::fs::metadata(&path)
                .map(|m| m.is_file() && m.len() > MIN_DOWNLOADED_BYTES)
                .unwrap_or(false);
            WhisperModelInfo {
                name: name.to_string(),
                filename,
                size: size.to_string(),
                downloaded,
                path: path.to_string_lossy().to_string(),
            }
        })
        .collect()
}

/// Download a Whisper GGML model from Hugging Face, streaming to a temp file
/// and atomically renaming on success. Emits throttled `whisper-download-progress`
/// events. Returns the final path on success, or an error message.
#[tauri::command]
pub async fn download_whisper_model(
    app: tauri::AppHandle,
    name: String,
) -> Result<String, String> {
    // Validate against catalog.
    if !CATALOG.iter().any(|(n, _)| *n == name) {
        return Err(format!("Unknown model: {}", name));
    }

    let dir = models_directory();
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create models dir: {}", e))?;

    let filename = filename_for(&name);
    let final_path = dir.join(&filename);
    let part_path = dir.join(format!("{}.part", filename));
    let url = format!("{}/{}", HF_BASE, filename);

    // Clean up any leftover partial from a previous attempt.
    let _ = std::fs::remove_file(&part_path);

    let result = download_to_part(&app, &name, &url, &part_path).await;

    match result {
        Ok(()) => {
            // Atomic rename so a partial download is never seen as "downloaded".
            if let Err(e) = std::fs::rename(&part_path, &final_path) {
                let _ = std::fs::remove_file(&part_path);
                return Err(format!("Failed to finalize download: {}", e));
            }
            Ok(final_path.to_string_lossy().to_string())
        }
        Err(e) => {
            let _ = std::fs::remove_file(&part_path);
            Err(e)
        }
    }
}

/// Delete a downloaded Whisper model file from the managed directory.
/// Succeeds (no-op) if the file is already gone.
#[tauri::command]
pub fn delete_whisper_model(name: String) -> Result<(), String> {
    if !CATALOG.iter().any(|(n, _)| *n == name) {
        return Err(format!("Unknown model: {}", name));
    }
    let path = models_directory().join(filename_for(&name));
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("Failed to delete model: {}", e)),
    }
}

async fn download_to_part(
    app: &tauri::AppHandle,
    name: &str,
    url: &str,
    part_path: &std::path::Path,
) -> Result<(), String> {
    use std::io::Write;

    let client = reqwest::Client::new();
    let resp = client
        .get(url)
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("Download failed: HTTP {}", resp.status()));
    }

    let total = resp.content_length().unwrap_or(0);

    let mut file =
        std::fs::File::create(part_path).map_err(|e| format!("Failed to create file: {}", e))?;

    let mut downloaded: u64 = 0;
    let mut last_emit = Instant::now();
    let mut last_emit_bytes: u64 = 0;
    let mut stream = resp.bytes_stream();

    // Emit an initial 0% event.
    emit_progress(app, name, 0, total);

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("Download error: {}", e))?;
        file.write_all(&chunk)
            .map_err(|e| format!("Failed to write file: {}", e))?;
        downloaded += chunk.len() as u64;

        // Throttle: at most ~every 200ms or every ~1MB.
        if last_emit.elapsed() >= Duration::from_millis(200)
            || downloaded - last_emit_bytes >= 1_000_000
        {
            emit_progress(app, name, downloaded, total);
            last_emit = Instant::now();
            last_emit_bytes = downloaded;
        }
    }

    file.flush().map_err(|e| format!("Failed to flush file: {}", e))?;

    // Final 100% event.
    emit_progress(app, name, downloaded, total);

    Ok(())
}

fn emit_progress(app: &tauri::AppHandle, name: &str, downloaded: u64, total: u64) {
    let _ = app.emit(
        "whisper-download-progress",
        serde_json::json!({
            "name": name,
            "downloaded": downloaded,
            "total": total,
        }),
    );
}
