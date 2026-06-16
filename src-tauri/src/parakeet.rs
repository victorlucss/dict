//! NVIDIA Parakeet (and other NeMo transducer) STT via sherpa-onnx (sherpa-rs).
//!
//! Mirrors `whisper.rs`: the recognizer is loaded once into a warm, in-memory
//! cache keyed by the model directory and reused for every dictation, so we never
//! pay the multi-second load again after the first transcription. Parakeet TDT
//! v3 is multilingual (auto-detects, no language flag) and runs many times faster
//! than realtime, so there's no language parameter here.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use sherpa_rs::transducer::{TransducerConfig, TransducerRecognizer};

/// A loaded recognizer kept warm in memory. Keyed by the model directory so
/// switching models reloads it.
struct WarmRecognizer {
    dir: String,
    rec: TransducerRecognizer,
}

fn warm_recognizer() -> &'static Mutex<Option<WarmRecognizer>> {
    static CACHE: OnceLock<Mutex<Option<WarmRecognizer>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

/// The four files a NeMo transducer bundle needs. Filenames vary across packagings
/// (e.g. `encoder.int8.onnx` vs `encoder.onnx`), so we resolve them by role rather
/// than hardcoding. Returns an error naming the first missing piece.
struct TransducerFiles {
    encoder: String,
    decoder: String,
    joiner: String,
    tokens: String,
}

fn resolve_files(dir: &Path) -> Result<TransducerFiles, String> {
    let entries: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("Can't read model dir {}: {}", dir.display(), e))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .collect();

    // Pick the .onnx whose filename contains `role`, preferring an int8 variant
    // (smaller/faster) when both are present.
    let pick_onnx = |role: &str| -> Option<String> {
        let mut matches: Vec<&PathBuf> = entries
            .iter()
            .filter(|p| {
                p.extension().map(|e| e == "onnx").unwrap_or(false)
                    && p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.to_lowercase().contains(role))
                        .unwrap_or(false)
            })
            .collect();
        // int8 first.
        matches.sort_by_key(|p| {
            let n = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
            !n.contains("int8") // false (int8) sorts before true
        });
        matches
            .first()
            .map(|p| p.to_string_lossy().to_string())
    };

    let tokens = dir.join("tokens.txt");
    if !tokens.exists() {
        return Err(format!("Missing tokens.txt in {}", dir.display()));
    }

    Ok(TransducerFiles {
        encoder: pick_onnx("encoder").ok_or("Missing encoder .onnx")?,
        decoder: pick_onnx("decoder").ok_or("Missing decoder .onnx")?,
        joiner: pick_onnx("joiner").ok_or("Missing joiner .onnx")?,
        tokens: tokens.to_string_lossy().to_string(),
    })
}

/// True if `dir` looks like a complete transducer model bundle. Used by the
/// model catalog to report download status.
pub fn is_complete_model_dir(dir: &Path) -> bool {
    dir.is_dir() && resolve_files(dir).is_ok()
}

/// Transcribe 16 kHz mono f32 samples with the Parakeet model at `model_dir`.
/// Loads + warms the recognizer on first use (or when the model changes).
pub fn transcribe(model_dir: &str, samples: &[f32]) -> Result<String, String> {
    if model_dir.is_empty() {
        return Err("No Parakeet model selected".to_string());
    }
    let dir = Path::new(model_dir);
    if !dir.is_dir() {
        return Err(format!("Parakeet model not found at: {}", model_dir));
    }
    if samples.is_empty() {
        return Ok(String::new());
    }

    let mut guard = warm_recognizer()
        // A poisoned lock would otherwise permanently disable dictation; recover
        // the inner value and carry on (the recognizer itself is unaffected).
        .lock()
        .unwrap_or_else(|p| p.into_inner());

    let needs_load = match guard.as_ref() {
        Some(w) => w.dir != model_dir,
        None => true,
    };
    if needs_load {
        let files = resolve_files(dir)?;
        tracing::info!("Loading Parakeet model into memory: {}", model_dir);

        let threads = std::thread::available_parallelism()
            .map(|n| n.get().min(8) as i32)
            .unwrap_or(4);

        let config = TransducerConfig {
            encoder: files.encoder,
            decoder: files.decoder,
            joiner: files.joiner,
            tokens: files.tokens,
            num_threads: threads,
            sample_rate: 16_000,
            feature_dim: 80,
            model_type: "nemo_transducer".to_string(),
            debug: false,
            ..Default::default()
        };

        let rec = TransducerRecognizer::new(config)
            .map_err(|e| format!("Failed to load Parakeet model: {}", e))?;
        *guard = Some(WarmRecognizer {
            dir: model_dir.to_string(),
            rec,
        });
        tracing::info!("Parakeet model loaded and warm");
    }

    let rec = &mut guard.as_mut().unwrap().rec;
    let text = rec.transcribe(16_000, samples);
    let text = text.trim();

    // Reject degenerate output (empty, or no letters/digits) — same gate as whisper.
    if text.is_empty() || !text.chars().any(|c| c.is_alphanumeric()) {
        tracing::info!("Rejecting non-speech Parakeet output ({} chars)", text.chars().count());
        return Ok(String::new());
    }
    Ok(text.to_string())
}

/// Drop the warm recognizer (e.g. after the active model is deleted) so the next
/// transcription reloads rather than using a freed model.
pub fn reset_warm_model() {
    let mut guard = warm_recognizer().lock().unwrap_or_else(|p| p.into_inner());
    *guard = None;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end check through Dict's own parakeet module. Ignored by default
    /// (needs a downloaded model + audio + the sherpa dylibs on the loader path):
    ///   DYLD_LIBRARY_PATH=target/debug \
    ///   DICT_TEST_PARAKEET_DIR=/path/to/model-dir \
    ///   DICT_TEST_WAV=/path/to/16k.wav \
    ///   cargo test -- --ignored parakeet_transcribes_real_audio --nocapture
    #[test]
    #[ignore]
    fn parakeet_transcribes_real_audio() {
        let dir = std::env::var("DICT_TEST_PARAKEET_DIR").expect("set DICT_TEST_PARAKEET_DIR");
        let wav = std::env::var("DICT_TEST_WAV").expect("set DICT_TEST_WAV");
        let (samples, sr) = sherpa_rs::read_audio_file(&wav).expect("read wav");
        assert_eq!(sr, 16_000, "test wav must be 16kHz");

        let text = transcribe(&dir, &samples).expect("transcribe");
        eprintln!("Parakeet result: {text:?}");
        assert!(!text.trim().is_empty(), "expected non-empty transcription");

        // Warm reuse: a second call must not reload (and must still work).
        let again = transcribe(&dir, &samples).expect("transcribe again");
        assert_eq!(text, again, "warm recognizer should give identical output");
    }
}
