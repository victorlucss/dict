use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Stream};
use rubato::{FftFixedIn, Resampler};
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

/// Shared state for audio recording
struct RecordingState {
    samples: Vec<f32>,
    sample_rate: u32,
    channels: u16,
}

/// Active audio capture session
pub struct AudioCapture {
    stream: SendStream,
    state: Arc<Mutex<RecordingState>>,
    level_callback: Arc<Mutex<Option<Box<dyn Fn(f32) + Send + 'static>>>>,
}

impl AudioCapture {
    pub fn new() -> Self {
        Self {
            stream: SendStream(None),
            state: Arc::new(Mutex::new(RecordingState {
                samples: Vec::new(),
                sample_rate: 44100,
                channels: 1,
            })),
            level_callback: Arc::new(Mutex::new(None)),
        }
    }

    pub fn set_level_callback<F: Fn(f32) + Send + 'static>(&self, callback: F) {
        *self.level_callback.lock().unwrap() = Some(Box::new(callback));
    }

    /// Start recording from the microphone
    pub fn start(&mut self, device_id: Option<&str>) -> Result<(), String> {
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
        }

        let state = self.state.clone();
        let level_cb = self.level_callback.clone();

        let stream = device
            .build_input_stream(
                &config.into(),
                move |data: &[f32], _: &cpal::InputCallbackInfo| {
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
                        s.samples.extend_from_slice(&mono_samples);
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

    /// Stop recording and return the captured audio as 16 kHz mono f32 samples,
    /// ready to feed straight into whisper-rs (no disk round-trip).
    pub fn stop(&mut self) -> Result<Vec<f32>, String> {
        self.stream = SendStream(None); // Drop the stream to stop recording
        tracing::info!("Audio capture stopped");

        let (samples, source_rate, _channels) = {
            let mut s = self.state.lock().unwrap();
            // Move the buffer out instead of cloning it (recording is over).
            (std::mem::take(&mut s.samples), s.sample_rate, s.channels)
        };

        if samples.is_empty() {
            return Err("No audio captured".to_string());
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

