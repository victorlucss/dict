use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Stream};
use rubato::{FftFixedIn, Resampler};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// Audio device info returned to the frontend
#[derive(Debug, Clone, serde::Serialize)]
pub struct AudioDeviceInfo {
    pub id: String,
    pub name: String,
}

/// Wrapper to make cpal::Stream Send+Sync (safe because we protect with Mutex).
/// The field is never read directly — it exists to keep the stream alive (RAII);
/// replacing it with `SendStream(None)` drops the stream and stops capture.
struct SendStream(#[allow(dead_code)] Option<Stream>);
// SAFETY: Stream is only accessed through a Mutex<AudioCapture> which serializes access.
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

/// Lists available audio input devices
pub fn list_audio_devices() -> Vec<AudioDeviceInfo> {
    let host = cpal::default_host();
    let mut devices = Vec::new();

    devices.push(AudioDeviceInfo {
        id: "default".to_string(),
        name: "System Default".to_string(),
    });

    if let Ok(input_devices) = host.input_devices() {
        for device in input_devices {
            if let Ok(name) = device.name() {
                devices.push(AudioDeviceInfo {
                    id: name.clone(),
                    name,
                });
            }
        }
    }

    devices
}

/// Get the input device by name, or the default
fn get_input_device(device_id: Option<&str>) -> Option<Device> {
    let host = cpal::default_host();

    match device_id {
        Some(id) if id != "default" => {
            if let Ok(devices) = host.input_devices() {
                for device in devices {
                    if let Ok(name) = device.name() {
                        if name == id {
                            return Some(device);
                        }
                    }
                }
            }
            // Fallback to default if specified device not found
            host.default_input_device()
        }
        _ => host.default_input_device(),
    }
}

/// Hard safety cap on a single recording. A recording that never stops (missed
/// push-to-talk release, forgotten toggle) grows the sample buffer ~690MB/hour
/// at 48kHz — left overnight that exhausts memory and panics the machine. The
/// capture callback stops buffering at this mark, and the recording watchdog in
/// lib.rs auto-stops the session at the same mark.
pub const MAX_RECORDING_SECS: u64 = 600;

/// Shared state for audio recording
struct RecordingState {
    samples: Vec<f32>,
    sample_rate: u32,
    channels: u16,
    /// Cap on `samples` length (mono frames), derived from the device sample rate.
    max_samples: usize,
    /// True once the cap was hit (so we log the drop only once).
    capped: bool,
}

impl RecordingState {
    /// Append captured mono samples, never growing past `max_samples`. Logs the
    /// cap once. Extracted from the capture callback so it's unit-testable
    /// without a real audio device.
    fn push_samples(&mut self, mono: &[f32]) {
        let room = self.max_samples.saturating_sub(self.samples.len());
        if room == 0 {
            if !self.capped {
                self.capped = true;
                tracing::warn!(
                    "Recording hit the {}s safety cap; dropping further audio",
                    MAX_RECORDING_SECS
                );
            }
        } else {
            let take = mono.len().min(room);
            self.samples.extend_from_slice(&mono[..take]);
        }
    }
}

/// Active audio capture session
pub struct AudioCapture {
    stream: SendStream,
    state: Arc<Mutex<RecordingState>>,
    level_callback: Arc<Mutex<Option<Box<dyn Fn(f32) + Send + 'static>>>>,
    /// Gate the capture callback reads before doing anything. Dropping a cpal
    /// input stream does NOT reliably tear down the CoreAudio unit on macOS —
    /// the callback can keep firing after `stop()`. Without this gate a "stopped"
    /// stream keeps appending to the shared buffer (and emitting level events)
    /// forever; with several recordings' worth leaked, the buffer fills at N×
    /// realtime and exhausts memory overnight. `stop()` flips this to false so
    /// any still-living callback becomes a no-op.
    active: Arc<AtomicBool>,
}

impl AudioCapture {
    pub fn new() -> Self {
        Self {
            stream: SendStream(None),
            state: Arc::new(Mutex::new(RecordingState {
                samples: Vec::new(),
                sample_rate: 44100,
                channels: 1,
                max_samples: 44100 * MAX_RECORDING_SECS as usize,
                capped: false,
            })),
            level_callback: Arc::new(Mutex::new(None)),
            active: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn set_level_callback<F: Fn(f32) + Send + 'static>(&self, callback: F) {
        *self.level_callback.lock().unwrap() = Some(Box::new(callback));
    }

    /// Start recording from the microphone
    pub fn start(&mut self, device_id: Option<&str>) -> Result<(), String> {
        // Tear down any stream still held from a prior session before building a
        // new one, so we never leak a reference to a running CoreAudio unit.
        self.stop_stream();

        let device = get_input_device(device_id).ok_or("No audio input device found")?;
        let config = device
            .default_input_config()
            .map_err(|e| format!("Failed to get input config: {}", e))?;

        let sample_rate = config.sample_rate().0;
        let channels = config.channels();

        tracing::info!(
            "Audio capture: {} @ {}Hz, {} ch",
            device.name().unwrap_or_default(),
            sample_rate,
            channels
        );

        {
            let mut s = self.state.lock().unwrap();
            s.samples.clear();
            s.sample_rate = sample_rate;
            s.channels = channels;
            s.max_samples = sample_rate as usize * MAX_RECORDING_SECS as usize;
            s.capped = false;
        }

        let state = self.state.clone();
        let level_cb = self.level_callback.clone();
        let active = self.active.clone();
        // Arm the gate before the stream starts producing callbacks.
        self.active.store(true, Ordering::SeqCst);

        let stream = device
            .build_input_stream(
                &config.into(),
                move |data: &[f32], _: &cpal::InputCallbackInfo| {
                    // A stopped (or leaked) stream's callback must do nothing.
                    if !active.load(Ordering::Relaxed) {
                        return;
                    }
                    // Collect samples (mono-mix if multi-channel)
                    let ch = channels as usize;
                    let mono_samples: Vec<f32> = if ch == 1 {
                        data.to_vec()
                    } else {
                        data.chunks(ch)
                            .map(|frame| frame.iter().sum::<f32>() / ch as f32)
                            .collect()
                    };

                    // Reactive level meter: blend RMS (body) with peak (snappy
                    // transients) so the wave actually dances with the voice
                    // instead of pinning at max. Tune the gains to taste.
                    let n = mono_samples.len().max(1) as f32;
                    let sum: f32 = mono_samples.iter().map(|s| s * s).sum();
                    let rms = (sum / n).sqrt();
                    let peak = mono_samples
                        .iter()
                        .fold(0.0_f32, |m, &s| m.max(s.abs()));
                    // Sensitive but gated: high RMS-weighted gain so the bars react
                    // strongly to speech, with a small noise gate below which the
                    // bars rest flat (background hum/room tone). RMS-dominant so
                    // background peak spikes (clicks/breaths) don't leak through.
                    // Tunable: raise GATE if idle noise shows; raise gains for more
                    // sensitivity.
                    let raw = rms * 46.0 + peak * 8.0;
                    const GATE: f32 = 0.10;
                    let normalized = if raw <= GATE {
                        0.0
                    } else {
                        ((raw - GATE) / (1.0 - GATE)).min(1.0)
                    };

                    if let Ok(cb) = level_cb.lock() {
                        if let Some(ref callback) = *cb {
                            callback(normalized);
                        }
                    }

                    if let Ok(mut s) = state.lock() {
                        s.push_samples(&mono_samples);
                    }
                },
                move |err| {
                    tracing::error!("Audio capture error: {}", err);
                },
                None,
            )
            .map_err(|e| format!("Failed to build input stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start stream: {}", e))?;

        self.stream = SendStream(Some(stream));
        tracing::info!("Audio capture started");
        Ok(())
    }

    /// Disarm the gate, explicitly pause the stream (CoreAudio's unit is NOT
    /// reliably stopped by dropping the `Stream` on macOS), then drop it. Safe to
    /// call with no active stream.
    fn stop_stream(&mut self) {
        self.active.store(false, Ordering::SeqCst);
        if let Some(stream) = self.stream.0.take() {
            let _ = stream.pause();
            // `stream` dropped here, after it was explicitly paused.
        }
    }

    /// Stop recording and return the captured audio as 16 kHz mono f32 samples,
    /// ready to feed straight into whisper-rs (no disk round-trip).
    pub fn stop(&mut self) -> Result<Vec<f32>, String> {
        self.stop_stream();
        tracing::info!("Audio capture stopped");

        let (samples, source_rate, _channels) = {
            let mut s = self.state.lock().unwrap();
            // Move the buffer out instead of cloning it (recording is over).
            (std::mem::take(&mut s.samples), s.sample_rate, s.channels)
        };

        if samples.is_empty() {
            return Err("No audio captured".to_string());
        }

        // Reject clips too short to hold a real utterance (sub-300ms, e.g. an
        // accidental hotkey tap) — feeding those to Whisper just makes it
        // hallucinate. 0.3s still leaves room for one-word dictations.
        let min_samples = (source_rate as usize * 3) / 10;
        if samples.len() < min_samples {
            return Err("Recording too short".to_string());
        }

        tracing::info!(
            "Captured {} samples at {}Hz",
            samples.len(),
            source_rate
        );

        // Resample to 16kHz if needed
        let resampled = if source_rate != 16000 {
            resample(&samples, source_rate, 16000)?
        } else {
            samples
        };

        tracing::info!("Resampled to 16kHz: {} frames", resampled.len());

        Ok(resampled)
    }
}

/// Resample audio from source_rate to target_rate using rubato
fn resample(samples: &[f32], source_rate: u32, target_rate: u32) -> Result<Vec<f32>, String> {
    let mut resampler = FftFixedIn::<f32>::new(
        source_rate as usize,
        target_rate as usize,
        1024,
        1, // sub-chunks
        1, // channels
    )
    .map_err(|e| format!("Failed to create resampler: {}", e))?;

    // Pre-size the output to the expected resampled length to avoid reallocations.
    let est_out =
        ((samples.len() as u64 * target_rate as u64) / source_rate.max(1) as u64) as usize;
    let mut output = Vec::with_capacity(est_out + 1024);
    let chunk_size = resampler.input_frames_next();

    let mut pos = 0;
    while pos < samples.len() {
        let end = (pos + chunk_size).min(samples.len());
        let mut chunk = samples[pos..end].to_vec();

        // Pad last chunk if needed
        if chunk.len() < chunk_size {
            chunk.resize(chunk_size, 0.0);
        }

        let input = vec![chunk];
        let result = resampler
            .process(&input, None)
            .map_err(|e| format!("Resampling error: {}", e))?;

        if let Some(channel) = result.first() {
            output.extend_from_slice(channel);
        }

        pos += chunk_size;
    }

    tracing::info!(
        "Resampled {} → {} frames ({}Hz → {}Hz)",
        samples.len(),
        output.len(),
        source_rate,
        target_rate
    );

    Ok(output)
}


#[cfg(test)]
mod tests {
    use super::*;

    fn state(max_samples: usize) -> RecordingState {
        RecordingState {
            samples: Vec::new(),
            sample_rate: 16000,
            channels: 1,
            max_samples,
            capped: false,
        }
    }

    #[test]
    fn push_samples_appends_below_cap() {
        let mut s = state(10);
        s.push_samples(&[0.1, 0.2, 0.3]);
        assert_eq!(s.samples.len(), 3);
        assert!(!s.capped);
    }

    #[test]
    fn push_samples_never_exceeds_cap_and_flags_when_full() {
        let mut s = state(4);
        s.push_samples(&[0.0, 0.1, 0.2]); // 3 -> under cap
        assert!(!s.capped);
        s.push_samples(&[0.3, 0.4, 0.5]); // would be 6; clamped to 4
        assert_eq!(s.samples.len(), 4, "buffer must not grow past the cap");

        // The next push finds no room: it's dropped and the cap is flagged once.
        s.push_samples(&[0.6, 0.7]);
        assert_eq!(s.samples.len(), 4, "buffer must not grow once full");
        assert!(s.capped, "cap flag set when a push finds the buffer full");

        // Still capped, still bounded on subsequent pushes.
        s.push_samples(&[0.8]);
        assert_eq!(s.samples.len(), 4);
    }
}
