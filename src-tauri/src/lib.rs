mod audio;
mod frontmost_app;
mod hotkey;
mod llm;
mod logging;
mod settings;
mod text_injector;
mod update_checker;
mod whisper;

use audio::AudioCapture;
use settings::{
    AppSettings, CustomDictionary, SettingsData, SnippetsStore, TranscriptionHistory,
    VoiceCommandsStore,
};
use std::sync::Mutex;
use std::time::Instant;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::{AppHandle, Emitter, Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_global_shortcut::ShortcutState;

pub struct AppState {
    pub settings: Mutex<AppSettings>,
    pub dictionary: Mutex<CustomDictionary>,
    pub snippets: Mutex<SnippetsStore>,
    pub commands: Mutex<VoiceCommandsStore>,
    pub history: Mutex<TranscriptionHistory>,
    pub audio_capture: Mutex<AudioCapture>,
    pub is_recording: Mutex<bool>,
    pub recording_stopped_at: Mutex<Option<Instant>>,
    /// Incremented on each recording start so a stale auto-stop timer
    /// from a previous recording can't stop a newer one.
    pub recording_generation: Mutex<u64>,
}

// ─── Tauri Commands ─────────────────────────────────────

#[tauri::command]
fn get_settings(state: tauri::State<'_, AppState>) -> Result<SettingsData, String> {
    let s = state.settings.lock().map_err(|e| e.to_string())?;
    Ok(s.data.clone())
}

#[tauri::command]
fn save_settings(state: tauri::State<'_, AppState>, data: SettingsData) -> Result<(), String> {
    let mut s = state.settings.lock().map_err(|e| e.to_string())?;
    s.data = data;
    s.save().map_err(|e| e.to_string())
}

#[tauri::command]
fn get_platform() -> String {
    if cfg!(target_os = "macos") {
        "macos".to_string()
    } else if cfg!(target_os = "windows") {
        "windows".to_string()
    } else {
        "linux".to_string()
    }
}

#[tauri::command]
fn list_audio_devices() -> Vec<audio::AudioDeviceInfo> {
    audio::list_audio_devices()
}

#[tauri::command]
fn check_accessibility() -> bool {
    text_injector::check_accessibility()
}

#[tauri::command]
fn get_frontmost_app_cmd() -> String {
    frontmost_app::get_frontmost_app()
}

#[tauri::command]
async fn check_for_update() -> update_checker::UpdateResult {
    update_checker::check_for_update().await
}

#[tauri::command]
fn get_history(state: tauri::State<'_, AppState>) -> Result<Vec<settings::HistoryEntry>, String> {
    let h = state.history.lock().map_err(|e| e.to_string())?;
    Ok(h.entries.clone())
}

#[tauri::command]
fn clear_history(state: tauri::State<'_, AppState>) -> Result<(), String> {
    let mut h = state.history.lock().map_err(|e| e.to_string())?;
    h.clear();
    Ok(())
}

#[tauri::command]
fn get_dictionary(state: tauri::State<'_, AppState>) -> Result<Vec<String>, String> {
    let d = state.dictionary.lock().map_err(|e| e.to_string())?;
    Ok(d.entries.clone())
}

#[tauri::command]
fn get_snippets(state: tauri::State<'_, AppState>) -> Result<Vec<settings::Snippet>, String> {
    let s = state.snippets.lock().map_err(|e| e.to_string())?;
    Ok(s.entries.clone())
}

#[tauri::command]
fn get_commands(
    state: tauri::State<'_, AppState>,
) -> Result<Vec<settings::VoiceCommand>, String> {
    let c = state.commands.lock().map_err(|e| e.to_string())?;
    Ok(c.entries.clone())
}

#[tauri::command]
fn save_dictionary(
    state: tauri::State<'_, AppState>,
    entries: Vec<String>,
) -> Result<(), String> {
    let mut d = state.dictionary.lock().map_err(|e| e.to_string())?;
    d.entries = entries;
    d.save().map_err(|e| e.to_string())
}

#[tauri::command]
fn save_snippets(
    state: tauri::State<'_, AppState>,
    entries: Vec<settings::Snippet>,
) -> Result<(), String> {
    let mut s = state.snippets.lock().map_err(|e| e.to_string())?;
    s.entries = entries;
    s.save().map_err(|e| e.to_string())
}

#[tauri::command]
fn save_commands(
    state: tauri::State<'_, AppState>,
    entries: Vec<settings::VoiceCommand>,
) -> Result<(), String> {
    let mut c = state.commands.lock().map_err(|e| e.to_string())?;
    c.entries = entries;
    c.save().map_err(|e| e.to_string())
}

#[tauri::command]
fn find_whisper_binary_cmd() -> Option<String> {
    whisper::find_whisper_binary().map(|p| p.to_string_lossy().to_string())
}

#[tauri::command]
fn open_accessibility_settings() {
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .spawn();
    }
}

#[tauri::command]
fn open_config_file(name: String) {
    let config_dir = if cfg!(target_os = "windows") {
        dirs::config_dir().unwrap_or_default().join("dict")
    } else {
        dirs::home_dir()
            .unwrap_or_default()
            .join(".config")
            .join("dict")
    };
    let path = config_dir.join(&name);
    // Open with system default editor
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(&path).spawn();
    }
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", "", &path.to_string_lossy()])
            .spawn();
    }
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("xdg-open").arg(&path).spawn();
    }
}

// ─── Window Management ──────────────────────────────────

fn open_preferences(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("preferences") {
        win.set_focus().ok();
        return;
    }

    WebviewWindowBuilder::new(
        app,
        "preferences",
        WebviewUrl::App("preferences/index.html".into()),
    )
    .title("Dict Preferences")
    .inner_size(620.0, 480.0)
    .resizable(false)
    .center()
    .build()
    .ok();
}

fn open_onboarding(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("onboarding") {
        win.set_focus().ok();
        return;
    }

    WebviewWindowBuilder::new(
        app,
        "onboarding",
        WebviewUrl::App("onboarding/index.html".into()),
    )
    .title("Dict Setup")
    .inner_size(480.0, 340.0)
    .resizable(false)
    .center()
    .build()
    .ok();
}

fn show_overlay(app: &AppHandle) {
    // Save the frontmost app BEFORE creating the overlay (so we can restore focus)
    #[cfg(target_os = "macos")]
    let prev_app = {
        use objc2_app_kit::NSWorkspace;
        NSWorkspace::sharedWorkspace().frontmostApplication()
    };

    if let Some(win) = app.get_webview_window("overlay") {
        win.show().ok();
        #[cfg(target_os = "macos")]
        restore_focus(prev_app);
        return;
    }

    let (verbose, position) = {
        let state = app.state::<AppState>();
        let s = state.settings.lock().unwrap();
        (s.data.verbose_overlay, s.data.overlay_position.clone())
    };

    let (width, height) = if verbose {
        (220.0, 60.0)
    } else {
        (140.0, 44.0)
    };

    let mut builder = WebviewWindowBuilder::new(
        app,
        "overlay",
        WebviewUrl::App("overlay/index.html".into()),
    )
    .title("Dict")
    .inner_size(width, height)
    .transparent(true)
    .decorations(false)
    .always_on_top(true)
    .skip_taskbar(true)
    .resizable(false)
    .focused(false)
    .focusable(false);

    // Position based on settings — get primary monitor dimensions
    if let Some(monitor) = app
        .primary_monitor()
        .ok()
        .flatten()
    {
        let screen_size = monitor.size();
        let scale = monitor.scale_factor();
        let screen_w = screen_size.width as f64 / scale;
        let screen_h = screen_size.height as f64 / scale;
        let x = (screen_w - width) / 2.0;
        let y = match position {
            settings::OverlayPosition::Top => 60.0,
            settings::OverlayPosition::Bottom => screen_h - height - 80.0,
        };
        builder = builder.position(x, y);
    } else {
        builder = builder.center();
    }

    match builder.build() {
        Ok(win) => {
            #[cfg(target_os = "macos")]
            {
                use objc2::msg_send;
                use objc2::runtime::AnyObject;

                let ns_win = win.ns_window().unwrap() as *mut AnyObject;
                unsafe {
                    // Ignore mouse events so clicks pass through — overlay is display-only
                    let _: () = msg_send![&*ns_win, setIgnoresMouseEvents: true];
                }
            }

            let _ = win.emit(
                "overlay-state",
                serde_json::json!({ "verbose": verbose }),
            );

            // Restore focus to the app the user was in before the overlay appeared
            #[cfg(target_os = "macos")]
            restore_focus(prev_app);
        }
        Err(e) => {
            tracing::error!("Failed to create overlay window: {}", e);
        }
    }
}

/// Reactivate the previously focused app after overlay steals focus
#[cfg(target_os = "macos")]
fn restore_focus(prev_app: Option<objc2::rc::Retained<objc2_app_kit::NSRunningApplication>>) {
    if let Some(app) = prev_app {
        #[allow(deprecated)]
        app.activateWithOptions(
            objc2_app_kit::NSApplicationActivationOptions::ActivateIgnoringOtherApps,
        );
    }
}

fn hide_overlay(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("overlay") {
        win.close().ok();
    }
}

fn show_accessibility_alert(_app: &AppHandle) {
    let _ = std::process::Command::new("open")
        .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        .spawn();
}

// ─── System Tray ────────────────────────────────────────

fn build_tray_menu(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let state = app.state::<AppState>();
    let settings = state.settings.lock().unwrap();

    let version_item = MenuItemBuilder::with_id(
        "version",
        format!("Dict v{}", env!("CARGO_PKG_VERSION")),
    )
    .enabled(false)
    .build(app)?;
    let toggle_item = MenuItemBuilder::with_id(
        "mode_toggle",
        if settings.data.hotkey_mode == settings::HotkeyMode::Toggle {
            "✓ Toggle Mode"
        } else {
            "  Toggle Mode"
        },
    )
    .build(app)?;
    let ptt_item = MenuItemBuilder::with_id(
        "mode_ptt",
        if settings.data.hotkey_mode == settings::HotkeyMode::PushToTalk {
            "✓ Push to Talk"
        } else {
            "  Push to Talk"
        },
    )
    .build(app)?;
    let record_item = MenuItemBuilder::with_id("toggle_record", "Start Recording").build(app)?;
    let prefs_item = MenuItemBuilder::with_id("preferences", "Preferences...").build(app)?;
    let update_item =
        MenuItemBuilder::with_id("check_update", "Check for Updates...").build(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&version_item)
        .separator()
        .item(&record_item)
        .separator()
        .item(&toggle_item)
        .item(&ptt_item)
        .separator()
        .item(&prefs_item)
        .item(&update_item)
        .separator()
        .item(&quit_item)
        .build()?;

    if let Some(tray) = app.tray_by_id("main-tray") {
        tray.set_menu(Some(menu))?;
    }

    Ok(())
}

// ─── Recording Orchestration ────────────────────────────

fn start_recording(app: &AppHandle) {
    let state = app.state::<AppState>();

    {
        let is_rec = state.is_recording.lock().unwrap();
        if *is_rec {
            return;
        }
    }

    let (device_id, language) = {
        let s = state.settings.lock().unwrap();
        (
            s.data.audio_input_device.clone(),
            s.data.whisper_language.clone(),
        )
    };

    tracing::info!("Engine: Whisper, Language: {}", language);

    {
        let app_handle = app.clone();
        let mut capture = state.audio_capture.lock().unwrap();

        capture.set_level_callback(move |level| {
            app_handle.emit("audio-level", level).ok();
        });

        let dev = device_id.as_deref();
        if let Err(e) = capture.start(dev) {
            tracing::error!("Failed to start audio capture: {}", e);
            return;
        }
    }

    let generation = {
        let mut is_rec = state.is_recording.lock().unwrap();
        *is_rec = true;
        let mut gen = state.recording_generation.lock().unwrap();
        *gen = gen.wrapping_add(1);
        *gen
    };

    tracing::info!("Recording started (engine: Whisper)");
    show_overlay(app);

    spawn_recording_timer(app, generation);
}

/// Background timer enforcing the 15-second hard recording limit.
/// Emits `recording-warning` to the overlay at 12s and hard-stops at 15s,
/// but only if this recording (identified by `generation`) is still the
/// active one — a stale timer from a previous recording is a no-op.
fn spawn_recording_timer(app: &AppHandle, generation: u64) {
    let app = app.clone();
    std::thread::spawn(move || {
        // Returns true if recording is still active AND this timer owns it.
        let still_owns = |app: &AppHandle| -> bool {
            let state = app.state::<AppState>();
            let is_rec = *state.is_recording.lock().unwrap();
            let gen = *state.recording_generation.lock().unwrap();
            is_rec && gen == generation
        };

        // 12s → warning
        std::thread::sleep(std::time::Duration::from_secs(12));
        if !still_owns(&app) {
            return;
        }
        if let Some(win) = app.get_webview_window("overlay") {
            let _ = win.emit("recording-warning", ());
        }

        // +3s (15s total) → hard stop
        std::thread::sleep(std::time::Duration::from_secs(3));
        if !still_owns(&app) {
            return;
        }
        tracing::info!("Recording hit 15s hard limit, auto-stopping");
        stop_recording(&app);
    });
}

fn stop_recording(app: &AppHandle) {
    let state = app.state::<AppState>();

    {
        let is_rec = state.is_recording.lock().unwrap();
        if !*is_rec {
            return;
        }
    }

    {
        let mut is_rec = state.is_recording.lock().unwrap();
        *is_rec = false;
    }

    {
        let mut stopped = state.recording_stopped_at.lock().unwrap();
        *stopped = Some(Instant::now());
    }

    tracing::info!("Recording stopped");

    if let Some(win) = app.get_webview_window("overlay") {
        let _ = win.emit(
            "overlay-state",
            serde_json::json!({ "processing": true }),
        );
    }

    let wav_path = {
        let mut capture = state.audio_capture.lock().unwrap();
        capture.stop()
    };

    match wav_path {
        Ok(path) => {
            let app_handle = app.clone();
            std::thread::spawn(move || {
                let state = app_handle.state::<AppState>();
                let (model_path, language) = {
                    let s = state.settings.lock().unwrap();
                    (
                        s.data.whisper_model_path.clone(),
                        s.data.whisper_language.clone(),
                    )
                };

                match whisper::transcribe(&path, &model_path, &language) {
                    Ok(text) => handle_transcription(&app_handle, &text),
                    Err(e) => {
                        tracing::error!("Whisper error: {}", e);
                        hide_overlay(&app_handle);
                    }
                }
            });
        }
        Err(e) => {
            tracing::error!("Audio capture error: {}", e);
            hide_overlay(app);
        }
    }
}

fn handle_transcription(app: &AppHandle, text: &str) {
    if text.is_empty() {
        tracing::info!("Empty transcription, skipping.");
        hide_overlay(app);
        return;
    }

    let state = app.state::<AppState>();
    let stt_elapsed = {
        let stopped = state.recording_stopped_at.lock().unwrap();
        stopped.map(|t| t.elapsed().as_millis()).unwrap_or(0)
    };

    tracing::info!("Transcribed ({}ms): {}", stt_elapsed, text);

    // Check snippets
    {
        let snippets = state.snippets.lock().unwrap();
        if let Some(expansion) = snippets.match_trigger(text) {
            tracing::info!("Snippet matched: \"{}\" → expanding", text);
            hide_overlay(app);
            if !text_injector::inject_text(&expansion, false) {
                show_accessibility_alert(app);
            }
            return;
        }
    }

    // Check voice commands
    {
        let commands = state.commands.lock().unwrap();
        if let Some(key_combo) = commands.match_trigger(text) {
            tracing::info!("Voice command matched: \"{}\" → {}", text, key_combo);
            hide_overlay(app);
            text_injector::simulate_key_combo(&key_combo);
            return;
        }
    }

    // LLM processing
    let frontmost = frontmost_app::get_frontmost_app();
    let (settings_data, dictionary_entries) = {
        let s = state.settings.lock().unwrap();
        let d = state.dictionary.lock().unwrap();
        (s.data.clone(), d.entries.clone())
    };

    let text_owned = text.to_string();
    let app_handle = app.clone();

    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let cleaned = rt.block_on(llm::process(
            &text_owned,
            &settings_data,
            &frontmost,
            &dictionary_entries,
        ));

        tracing::info!("Final text: {}", cleaned);
        hide_overlay(&app_handle);

        let flow_mode = settings_data.flow_mode;
        if !text_injector::inject_text(&cleaned, flow_mode) {
            show_accessibility_alert(&app_handle);
        }

        // Privacy mode: don't persist transcription history to disk.
        if settings_data.privacy_mode {
            tracing::info!("Privacy mode on: not saving transcription to history");
        } else {
            let state = app_handle.state::<AppState>();
            let mut history = state.history.lock().unwrap();
            history.add(&text_owned, &cleaned, &frontmost, "Whisper");
        }
    });
}

// ─── App Entry Point ────────────────────────────────────

pub fn run() {
    logging::init();

    let app_settings = AppSettings::load();
    let show_onboarding = !app_settings.data.onboarding_done;
    tracing::info!("Dict starting up");
    tracing::info!("Engine: Whisper");
    tracing::info!(
        "LLM cleanup: {}",
        if app_settings.data.llm_enabled {
            "on"
        } else {
            "off"
        }
    );

    tauri::Builder::default()
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        let state = app.state::<AppState>();
                        let mode = {
                            let s = state.settings.lock().unwrap();
                            s.data.hotkey_mode.clone()
                        };

                        match mode {
                            settings::HotkeyMode::Toggle => {
                                if event.state == ShortcutState::Pressed {
                                    let is_rec = *state.is_recording.lock().unwrap();
                                    if is_rec {
                                        stop_recording(app);
                                    } else {
                                        start_recording(app);
                                    }
                                }
                            }
                            settings::HotkeyMode::PushToTalk => {
                                match event.state {
                                    ShortcutState::Pressed => {
                                        let is_rec = *state.is_recording.lock().unwrap();
                                        if !is_rec {
                                            start_recording(app);
                                        }
                                    }
                                    ShortcutState::Released => {
                                        let is_rec = *state.is_recording.lock().unwrap();
                                        if is_rec {
                                            stop_recording(app);
                                        }
                                    }
                                }
                            }
                        }
                    }));

                    if let Err(e) = result {
                        tracing::error!("Hotkey handler panicked: {:?}", e);
                    }
                })
                .build(),
        )
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState {
            settings: Mutex::new(app_settings),
            dictionary: Mutex::new(CustomDictionary::load()),
            snippets: Mutex::new(SnippetsStore::load()),
            commands: Mutex::new(VoiceCommandsStore::load()),
            history: Mutex::new(TranscriptionHistory::load()),
            audio_capture: Mutex::new(AudioCapture::new()),
            is_recording: Mutex::new(false),
            recording_stopped_at: Mutex::new(None),
            recording_generation: Mutex::new(0),
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            get_platform,
            list_audio_devices,
            check_accessibility,
            get_frontmost_app_cmd,
            check_for_update,
            get_history,
            clear_history,
            get_dictionary,
            save_dictionary,
            get_snippets,
            save_snippets,
            get_commands,
            save_commands,
            find_whisper_binary_cmd,
            open_accessibility_settings,
            open_config_file,
        ])
        .setup(move |app| {
            // Request all permissions on macOS at startup
            #[cfg(target_os = "macos")]
            {
                let app_handle = app.handle().clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs(1));
                    // Check accessibility — prompt user if not granted
                    if !text_injector::check_accessibility() {
                        show_accessibility_alert(&app_handle);
                    }
                });
            }

            // Register global hotkey
            {
                use tauri_plugin_global_shortcut::GlobalShortcutExt;
                let shortcut_str = hotkey::default_hotkey();
                if let Err(e) = app.global_shortcut().register(shortcut_str) {
                    tracing::error!("Failed to register hotkey '{}': {}", shortcut_str, e);
                } else {
                    tracing::info!("Registered hotkey: {}", shortcut_str);
                }
            }

            // Build system tray menu
            if let Err(e) = build_tray_menu(app.handle()) {
                tracing::error!("Failed to build tray menu: {}", e);
            }

            // Handle tray menu events
            let app_handle = app.handle().clone();
            if let Some(tray) = app.tray_by_id("main-tray") {
                tray.on_menu_event(move |_app, event| match event.id().as_ref() {
                    "toggle_record" => {
                        let state = app_handle.state::<AppState>();
                        let is_rec = *state.is_recording.lock().unwrap();
                        if is_rec {
                            stop_recording(&app_handle);
                        } else {
                            start_recording(&app_handle);
                        }
                    }
                    "preferences" => open_preferences(&app_handle),
                    "mode_toggle" => {
                        let state = app_handle.state::<AppState>();
                        let mut s = state.settings.lock().unwrap();
                        s.data.hotkey_mode = settings::HotkeyMode::Toggle;
                        let _ = s.save();
                        drop(s);
                        let _ = build_tray_menu(&app_handle);
                    }
                    "mode_ptt" => {
                        let state = app_handle.state::<AppState>();
                        let mut s = state.settings.lock().unwrap();
                        s.data.hotkey_mode = settings::HotkeyMode::PushToTalk;
                        let _ = s.save();
                        drop(s);
                        let _ = build_tray_menu(&app_handle);
                    }
                    "quit" => {
                        std::process::exit(0);
                    }
                    _ => {}
                });
            }

            // Show onboarding if first launch
            if show_onboarding {
                open_onboarding(app.handle());
            }

            tracing::info!(
                "Dict is running. Press {} to dictate.",
                hotkey::default_hotkey()
            );
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error building Dict")
        .run(|_app, event| {
            // Prevent app from exiting when all windows close (tray-only app)
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                api.prevent_exit();
            }
        });
}
