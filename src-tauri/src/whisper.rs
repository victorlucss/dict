use std::path::Path;
use std::sync::{Mutex, OnceLock};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// A loaded model kept warm in memory so we never reload it from disk between
/// dictations. Keyed by the model path so switching models reloads it.
struct WarmModel {
    path: String,
    ctx: WhisperContext,
}

fn warm_model() -> &'static Mutex<Option<WarmModel>> {
    static CACHE: OnceLock<Mutex<Option<WarmModel>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

/// Transcribe 16 kHz mono f32 samples in-process via whisper.cpp (whisper-rs).
///
/// The GGML model is loaded once into RAM (Metal-accelerated on Apple Silicon) and
/// reused for every subsequent dictation — eliminating the per-call subprocess
/// spawn + model reload that previously dominated latency.
pub fn transcribe(model_path: &str, samples: &[f32], language: &str) -> Result<String, String> {
    if model_path.is_empty() || !Path::new(model_path).exists() {
        return Err(format!("Whisper model not found at: {}", model_path));
    }
    if samples.is_empty() {
        return Ok(String::new());
    }

    let mut guard = warm_model()
        .lock()
        .map_err(|e| format!("whisper cache poisoned: {}", e))?;

    let needs_load = match guard.as_ref() {
        Some(w) => w.path != model_path,
        None => true,
    };
    if needs_load {
        tracing::info!("Loading Whisper model into memory: {}", model_path);
        let ctx = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
            .map_err(|e| format!("Failed to load Whisper model: {}", e))?;
        *guard = Some(WarmModel {
            path: model_path.to_string(),
            ctx,
        });
        tracing::info!("Whisper model loaded and warm");
    }
    let ctx = &guard.as_ref().unwrap().ctx;

    let mut state = ctx
        .create_state()
        .map_err(|e| format!("Failed to create Whisper state: {}", e))?;

    let threads = std::thread::available_parallelism()
        .map(|n| n.get().min(8) as i32)
        .unwrap_or(4);

    // Greedy decoding (beam size 1): markedly faster than beam search with
    // negligible accuracy loss on short, clean dictation.
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_n_threads(threads);
    if !language.is_empty() {
        // "auto" is a valid whisper language code (triggers detection).
        params.set_language(Some(language));
    }
    params.set_translate(false);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);

    state
        .full(params, samples)
        .map_err(|e| format!("Whisper inference failed: {}", e))?;

    let n = state.full_n_segments();
    let mut text = String::new();
    for i in 0..n {
        if let Some(seg) = state.get_segment(i) {
            if let Ok(s) = seg.to_str() {
                text.push_str(s);
            }
        }
    }

    Ok(text.trim().to_string())
}
