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

    // Anti-hallucination hardening for short single-shot dictation. The big one is
    // temperature_inc=0, which disables whisper.cpp's temperature fallback — the
    // retry-at-rising-temperature loop that fabricates fluent text (e.g. an entire
    // Icelandic sentence) out of silence/noise.
    params.set_temperature(0.0);
    params.set_temperature_inc(0.0);
    params.set_no_context(true); // never seed the decoder from prior text
    params.set_single_segment(true); // one clip -> at most one segment
    params.set_suppress_blank(true);
    params.set_suppress_nst(true); // suppress non-speech tokens

    state
        .full(params, samples)
        .map_err(|e| format!("Whisper inference failed: {}", e))?;

    // Confidence-gate each segment: the model's own no-speech probability and the
    // mean per-token probability flag noise/hallucinations, which we drop. This
    // catches the noise cases regardless of the (possibly auto-detected) language.
    const NO_SPEECH_THOLD: f32 = 0.6;
    // Lenient on purpose: only drop clearly low-confidence (garbage) segments so we
    // never discard real, quietly-spoken dictation. no_speech_prob is the primary gate.
    const MIN_AVG_TOKEN_PROB: f32 = 0.35;

    let n = state.full_n_segments();
    let mut text = String::new();
    for i in 0..n {
        let Some(seg) = state.get_segment(i) else {
            continue;
        };

        let no_speech = seg.no_speech_probability();
        if no_speech > NO_SPEECH_THOLD {
            tracing::info!("Dropping segment {}: no_speech_prob={:.2}", i, no_speech);
            continue;
        }

        let nt = seg.n_tokens();
        if nt > 0 {
            let mut sum = 0.0f32;
            for t in 0..nt {
                if let Some(tok) = seg.get_token(t) {
                    sum += tok.token_probability();
                }
            }
            let avg = sum / nt as f32;
            if avg < MIN_AVG_TOKEN_PROB {
                tracing::info!("Dropping segment {}: avg_token_prob={:.2}", i, avg);
                continue;
            }
        }

        if let Ok(s) = seg.to_str() {
            text.push_str(s);
        }
    }

    let text = text.trim();
    // Reject degenerate output: empty, or no actual letters/digits (e.g. ".").
    if text.is_empty() || !text.chars().any(|c| c.is_alphanumeric()) {
        tracing::info!("Rejecting non-speech transcription: {:?}", text);
        return Ok(String::new());
    }

    Ok(text.to_string())
}
