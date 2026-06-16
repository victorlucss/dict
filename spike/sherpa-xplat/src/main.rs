// Forces the native sherpa-onnx symbols to link (references TransducerRecognizer
// behind a runtime gate so it's not dead-code-eliminated). CI only *builds* this;
// the body never runs, so no model is needed. A successful build per-OS proves
// sherpa-rs `download-binaries` works on that platform.
fn main() {
    if std::env::var("RUN_PROBE").is_ok() {
        use sherpa_rs::transducer::{TransducerConfig, TransducerRecognizer};
        let _ = TransducerRecognizer::new(TransducerConfig::default());
    }
    println!("sherpa-rs linked OK on this platform");
}
