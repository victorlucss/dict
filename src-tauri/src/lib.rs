mod audio;
mod frontmost_app;
mod hotkey;
mod llm;
mod logging;
mod models;
mod settings;
mod text_injector;
mod update_checker;
mod updater;
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
    /// Transcription staged for the copy-fallback popup to fetch on load (set when
    /// a paste fails). Taken (cleared) by `get_fallback_text`.
    pub fallback_text: Mutex<Option<String>>,
}

// ─── Tauri Commands ─────────────────────────────────────

#[tauri::command]
fn get_settings(state: tauri::State<'_, AppState>) -> Result<SettingsData, String> {
    let s = state.settings.lock().map_err(|e| e.to_string())?;
    Ok(s.data.clone())
}

#[tauri::command]
fn save_settings(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    data: SettingsData,
) -> Result<(), String> {
    use tauri_plugin_global_shortcut::GlobalShortcutExt;

    let old_hotkey = {
        let s = state.settings.lock().map_err(|e| e.to_string())?;
        s.data.hotkey.clone()
    };
    let new_hotkey = data.hotkey.clone();

    // Re-register the global shortcut if the hotkey changed. Use on_shortcut (not
    // register) so the handler is attached — the builder-level handler does NOT
    // fire for runtime registrations. Register the new one first so we can reject
    // an invalid combo without losing the working hotkey.
    if new_hotkey != old_hotkey {
        let gs = app.global_shortcut();
        let handler = |app: &AppHandle, _sc: &_, event: tauri_plugin_global_shortcut::ShortcutEvent| {
            handle_hotkey_event(app, event.state);
        };
        // Register the new accelerator first (so an invalid one is rejected before
        // we drop the old). Bare modifiers / Fn aren't registered here — the native
        // monitor handles them by reading the saved setting below.
        if !is_bare_modifier(&new_hotkey) {
            if let Err(e) = gs.on_shortcut(new_hotkey.as_str(), handler) {
                return Err(format!("Invalid shortcut \"{}\": {}", new_hotkey, e));
            }
        }
        if !is_bare_modifier(&old_hotkey) {
            let _ = gs.unregister(old_hotkey.as_str());
        }
        tracing::info!("Hotkey changed: {} → {}", old_hotkey, new_hotkey);
    }

    let mut s = state.settings.lock().map_err(|e| e.to_string())?;
    // The Preferences form never sends the Dict Cloud session token/email, so
    // preserve them across auto-saves (only the auth commands change them).
    let mut data = data;
    if data.dict_cloud_token.is_empty() {
        data.dict_cloud_token = s.data.dict_cloud_token.clone();
    }
    if data.dict_cloud_email.is_empty() {
        data.dict_cloud_email = s.data.dict_cloud_email.clone();
    }
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
    tracing::info!("open_preferences called");
    if let Some(win) = app.get_webview_window("preferences") {
        win.show().ok();
        win.set_focus().ok();
        return;
    }

    let builder = WebviewWindowBuilder::new(
        app,
        "preferences",
        WebviewUrl::App("preferences/index.html".into()),
    )
    .title("")
    .inner_size(760.0, 600.0)
    .min_inner_size(640.0, 480.0)
    .resizable(true)
    .transparent(true)
    .center();

    // macOS: overlay title bar so content extends under the floating traffic lights
    #[cfg(target_os = "macos")]
    let builder = builder.title_bar_style(tauri::TitleBarStyle::Overlay);

    match builder.build() {
        Ok(_win) => {
            // macOS: apply a native translucent sidebar material behind the window.
            // The frontend keeps its content pane opaque and its sidebar transparent,
            // producing a translucent-sidebar look like macOS System Settings.
            #[cfg(target_os = "macos")]
            {
                use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial};
                if let Err(e) =
                    apply_vibrancy(&_win, NSVisualEffectMaterial::Sidebar, None, None)
                {
                    tracing::error!("Failed to apply window vibrancy: {}", e);
                }
            }
        }
        Err(e) => tracing::error!("Failed to open preferences window: {}", e),
    }
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
    .inner_size(560.0, 660.0)
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

    let position = {
        let state = app.state::<AppState>();
        let s = state.settings.lock().unwrap();
        s.data.overlay_position.clone()
    };

    let (width, height) = (72.0, 28.0);

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
            settings::OverlayPosition::Bottom => screen_h - height - 12.0,
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

/// Dict Cloud auth: POST {email, password} to `path`, store the returned token
/// + email on success. Shared by sign-up and sign-in.
async fn dict_cloud_auth(
    app: &tauri::AppHandle,
    path: &str,
    email: String,
    password: String,
    fail_msg: &str,
    store: bool,
) -> Result<String, String> {
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{}{}", llm::DICT_CLOUD_ENDPOINT, path))
        .json(&serde_json::json!({ "email": email, "password": password }))
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("Couldn't reach Dict Cloud: {}", e))?;

    let status = resp.status();
    let data: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| format!("Unexpected response: {}", e))?;
    if !status.is_success() {
        // Surface a couple of specific cases; otherwise the generic message.
        let err = data["error"].as_str().unwrap_or("");
        let msg = match err {
            "email_taken" => "That email already has an account. Sign in instead.",
            "weak_password" => "Password must be at least 8 characters.",
            "bad_email" => "Enter a valid email address.",
            _ => fail_msg,
        };
        return Err(msg.to_string());
    }
    // Sign-up creates the account but does NOT log in (store = false); the user
    // then signs in. Sign-in persists the returned session token (store = true).
    if store {
        let token = data["token"]
            .as_str()
            .ok_or("No token in response")?
            .to_string();
        let state = app.state::<AppState>();
        let mut s = state.settings.lock().map_err(|e| e.to_string())?;
        s.data.dict_cloud_token = token;
        s.data.dict_cloud_email = email.clone();
        s.save().map_err(|e| e.to_string())?;
    }
    Ok(email)
}

/// Dict Cloud: create an account with email + password (does not sign in).
#[tauri::command]
async fn dict_cloud_sign_up(
    app: tauri::AppHandle,
    email: String,
    password: String,
) -> Result<String, String> {
    dict_cloud_auth(
        &app,
        "/auth/signup",
        email,
        password,
        "Couldn't create the account.",
        false,
    )
    .await
}

/// Dict Cloud: sign in with email + password (persists the session token).
#[tauri::command]
async fn dict_cloud_sign_in(
    app: tauri::AppHandle,
    email: String,
    password: String,
) -> Result<String, String> {
    dict_cloud_auth(
        &app,
        "/auth/signin",
        email,
        password,
        "Wrong email or password.",
        true,
    )
    .await
}

/// Dict Cloud: fetch the signed-in account's status — feature flags, plan,
/// daily limit, and usage today. Returns the raw `/v1/flags` JSON.
#[tauri::command]
async fn dict_cloud_flags(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let token = {
        let state = app.state::<AppState>();
        let s = state.settings.lock().map_err(|e| e.to_string())?;
        s.data.dict_cloud_token.clone()
    };
    if token.is_empty() {
        return Err("Not signed in".to_string());
    }
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/v1/flags", llm::DICT_CLOUD_ENDPOINT))
        .header("Authorization", format!("Bearer {}", token))
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("Couldn't reach Dict Cloud: {}", e))?;
    if !resp.status().is_success() {
        return Err("Couldn't load account status.".to_string());
    }
    let data: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| format!("Unexpected response: {}", e))?;
    Ok(data)
}

/// Dict Cloud: sign out (clear the stored token + email).
#[tauri::command]
fn dict_cloud_sign_out(app: tauri::AppHandle) -> Result<(), String> {
    let state = app.state::<AppState>();
    let mut s = state.settings.lock().map_err(|e| e.to_string())?;
    s.data.dict_cloud_token.clear();
    s.data.dict_cloud_email.clear();
    s.save().map_err(|e| e.to_string())
}

/// Command: the copy-fallback popup pulls (and clears) its transcription on load.
#[tauri::command]
fn get_fallback_text(state: tauri::State<'_, AppState>) -> String {
    state
        .fallback_text
        .lock()
        .ok()
        .and_then(|mut t| t.take())
        .unwrap_or_default()
}

/// Show the copy-fallback popup with `text`. Called when a paste fails so the user
/// can still grab the transcription. Stages the text for the window to fetch, then
/// either refreshes an existing popup (restarting its countdown) or builds one.
fn show_fallback(app: &AppHandle, text: &str) {
    {
        let state = app.state::<AppState>();
        let guard = state.fallback_text.lock();
        if let Ok(mut t) = guard {
            *t = Some(text.to_string());
        }
    }

    // Already open: refresh its text + restart its countdown, don't rebuild.
    if let Some(win) = app.get_webview_window("fallback") {
        let _ = win.emit("fallback-show", text);
        return;
    }

    // Window creation must run on the main thread (we may be on the LLM thread).
    let app2 = app.clone();
    let _ = app.run_on_main_thread(move || build_fallback_window(&app2));
}

fn build_fallback_window(app: &AppHandle) {
    let width = 360.0;
    let height = 140.0;

    let mut builder = WebviewWindowBuilder::new(
        app,
        "fallback",
        WebviewUrl::App("fallback/index.html".into()),
    )
    .title("Dict")
    .inner_size(width, height)
    .transparent(true)
    .decorations(false)
    .always_on_top(true)
    .skip_taskbar(true)
    .resizable(false)
    // Don't steal key focus from the user's app; it stays clickable/hoverable.
    .focused(false);

    if let Some(monitor) = app.primary_monitor().ok().flatten() {
        let screen_size = monitor.size();
        let scale = monitor.scale_factor();
        let screen_w = screen_size.width as f64 / scale;
        let screen_h = screen_size.height as f64 / scale;
        let x = (screen_w - width) / 2.0;
        // Sit just above where the overlay bubble lives at the bottom.
        let y = screen_h - height - 48.0;
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
                use objc2_app_kit::NSColor;

                if let Ok(ptr) = win.ns_window() {
                    let ns_win = ptr as *mut AnyObject;
                    unsafe {
                        // Show on every Space and over fullscreen apps, and follow
                        // the user rather than staying pinned to the origin Space.
                        // canJoinAllSpaces(1) | stationary(16) | fullScreenAuxiliary(256)
                        let _: () = msg_send![&*ns_win, setCollectionBehavior: 273usize];
                        // Kill the transparent-window shadow that renders as a thin
                        // rectangular outline around the bubble.
                        let _: () = msg_send![&*ns_win, setHasShadow: false];
                        let _: () = msg_send![&*ns_win, setOpaque: false];
                        let clear = NSColor::clearColor();
                        let _: () = msg_send![&*ns_win, setBackgroundColor: &*clear];
                    }
                }
            }
        }
        Err(e) => tracing::error!("Failed to create fallback window: {}", e),
    }
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
    let prefs_item = MenuItemBuilder::with_id("preferences", "Preferences...").build(app)?;
    let update_item =
        MenuItemBuilder::with_id("check_update", "Check for Updates...").build(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&version_item)
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

    {
        let mut is_rec = state.is_recording.lock().unwrap();
        *is_rec = true;
    }

    tracing::info!("Recording started (engine: Whisper)");
    show_overlay(app);
    // No recording time limit — record for as long as the hotkey is held / toggled.
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

/// Stop recording and throw the audio away without transcribing. Used when the
/// user clearly didn't mean to dictate (e.g. they held a bare-modifier hotkey but
/// pressed another key, using it as a chord like Option+Arrow).
fn cancel_recording(app: &AppHandle) {
    let state = app.state::<AppState>();
    {
        let mut is_rec = state.is_recording.lock().unwrap();
        if !*is_rec {
            return;
        }
        *is_rec = false;
    }
    // Stop capture and discard the WAV; do not transcribe.
    let discarded = {
        let mut capture = state.audio_capture.lock().unwrap();
        capture.stop()
    };
    if let Ok(path) = discarded {
        let _ = std::fs::remove_file(path);
    }
    tracing::info!("Recording cancelled (hotkey used as a chord)");
    hide_overlay(app);
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
            // No editable field (or paste fails) → offer the text via the popup.
            if !text_injector::has_editable_focus()
                || !text_injector::inject_text(&expansion, false)
            {
                show_fallback(app, &expansion);
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

        // Broadcast the final text so UIs can react (e.g. the onboarding "try it"
        // step shows it). Harmless in normal use — nothing listens.
        let _ = app_handle.emit("transcription-result", &cleaned);

        let flow_mode = settings_data.flow_mode;
        // Give focus a moment to settle back on the user's app after the overlay
        // closes, then check there's somewhere to paste before sending Cmd+V.
        std::thread::sleep(std::time::Duration::from_millis(120));
        if !text_injector::has_editable_focus()
            || !text_injector::inject_text(&cleaned, flow_mode)
        {
            show_fallback(&app_handle, &cleaned);
        }

        // Privacy mode: don't persist transcription history to disk.
        if settings_data.privacy_mode {
            tracing::info!("Privacy mode on: not saving transcription to history");
        } else {
            // The text left the device for refinement when LLM cleanup ran via Dict Cloud.
            let cloud = settings_data.llm_enabled
                && matches!(settings_data.llm_provider, settings::LLMProvider::Dictcloud);
            let state = app_handle.state::<AppState>();
            let mut history = state.history.lock().unwrap();
            history.add(&text_owned, &cleaned, &frontmost, "Whisper", cloud);
        }
    });
}

/// Dispatch a global-hotkey event to start/stop recording based on the hotkey mode.
/// Registered via `on_shortcut` (not the builder's `with_handler`) so that hotkeys
/// re-registered at runtime (when the user changes the shortcut and saves) actually
/// fire — the builder-level handler is NOT invoked for runtime `register()` calls.
fn handle_hotkey_event(app: &AppHandle, shortcut_state: ShortcutState) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = app.state::<AppState>();
        let mode = {
            let s = state.settings.lock().unwrap();
            s.data.hotkey_mode.clone()
        };

        match mode {
            settings::HotkeyMode::Toggle => {
                if shortcut_state == ShortcutState::Pressed {
                    let is_rec = *state.is_recording.lock().unwrap();
                    if is_rec {
                        stop_recording(app);
                    } else {
                        start_recording(app);
                    }
                }
            }
            settings::HotkeyMode::PushToTalk => match shortcut_state {
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
            },
        }
    }));

    if let Err(e) = result {
        tracing::error!("Hotkey handler panicked: {:?}", e);
    }
}

// ─── Bare-modifier / Fn triggers (native key monitor) ───

/// True if the hotkey string is a single modifier / Fn key (not a normal
/// accelerator). These can't be registered as global shortcuts, so they're
/// handled by the native NSEvent monitor instead (macOS only).
fn is_bare_modifier(hotkey: &str) -> bool {
    matches!(
        hotkey,
        "Fn" | "Control"
            | "LeftControl"
            | "RightControl"
            | "Option"
            | "LeftOption"
            | "RightOption"
            | "Command"
            | "LeftCommand"
            | "RightCommand"
            | "Shift"
            | "LeftShift"
            | "RightShift"
    )
}

/// Map a bare-modifier token to its macOS virtual key code and the modifier flag
/// bit that goes on/off when that physical key is pressed/released.
#[cfg(target_os = "macos")]
fn bare_modifier_keycode_flag(hotkey: &str) -> Option<(u16, usize)> {
    const SHIFT: usize = 1 << 17;
    const CONTROL: usize = 1 << 18;
    const OPTION: usize = 1 << 19;
    const COMMAND: usize = 1 << 20;
    const FUNCTION: usize = 1 << 23;
    Some(match hotkey {
        "Fn" => (63, FUNCTION),
        "Control" | "LeftControl" => (59, CONTROL),
        "RightControl" => (62, CONTROL),
        "Option" | "LeftOption" => (58, OPTION),
        "RightOption" => (61, OPTION),
        "Command" | "LeftCommand" => (55, COMMAND),
        "RightCommand" => (54, COMMAND),
        "Shift" | "LeftShift" => (56, SHIFT),
        "RightShift" => (60, SHIFT),
        _ => return None,
    })
}

/// Called from the flagsChanged monitor. If the configured hotkey is a bare
/// modifier matching this physical key, treat its press/release as the hotkey.
#[cfg(target_os = "macos")]
fn dispatch_modifier_event(app: &AppHandle, keycode: u16, flags: usize) {
    let hk = {
        let state = app.state::<AppState>();
        let s = state.settings.lock().unwrap();
        s.data.hotkey.clone()
    };
    if let Some((kc, mask)) = bare_modifier_keycode_flag(&hk) {
        if keycode == kc {
            let down = (flags & mask) != 0;
            let ss = if down {
                ShortcutState::Pressed
            } else {
                ShortcutState::Released
            };
            handle_hotkey_event(app, ss);
        }
    }
}

/// Called from the keyDown monitor. If a bare-modifier hotkey is active and we're
/// currently recording, a real (non-modifier) keypress means the user is using the
/// modifier as a chord, not dictating, so cancel and discard the recording.
/// (Modifier keys themselves emit flagsChanged, not keyDown, so any keyDown here is
/// a genuine other key.)
#[cfg(target_os = "macos")]
fn dispatch_key_down(app: &AppHandle) {
    let (hk, recording) = {
        let state = app.state::<AppState>();
        let hk = state.settings.lock().unwrap().data.hotkey.clone();
        let recording = *state.is_recording.lock().unwrap();
        (hk, recording)
    };
    if recording && is_bare_modifier(&hk) {
        cancel_recording(app);
    }
}

/// Install an always-on NSEvent monitor for modifier-flag changes so a bare
/// modifier / Fn key can act as the dictation trigger. Installed once at startup
/// (main thread); it reads the current hotkey live, so changing the hotkey needs
/// no re-install. Requires Accessibility permission (already needed for pasting).
#[cfg(target_os = "macos")]
fn install_modifier_monitor(app: &AppHandle) {
    use objc2_app_kit::{NSEvent, NSEventMask};
    use std::ptr::NonNull;

    let app_global = app.clone();
    let global = block2::RcBlock::new(move |event: NonNull<NSEvent>| {
        let ev = unsafe { event.as_ref() };
        dispatch_modifier_event(&app_global, ev.keyCode(), ev.modifierFlags().0);
    });
    let _global_token =
        NSEvent::addGlobalMonitorForEventsMatchingMask_handler(NSEventMask::FlagsChanged, &global);
    std::mem::forget(global);

    let app_local = app.clone();
    let local = block2::RcBlock::new(move |event: NonNull<NSEvent>| -> *mut NSEvent {
        let ev = unsafe { event.as_ref() };
        dispatch_modifier_event(&app_local, ev.keyCode(), ev.modifierFlags().0);
        event.as_ptr()
    });
    let _local_token = unsafe {
        NSEvent::addLocalMonitorForEventsMatchingMask_handler(NSEventMask::FlagsChanged, &local)
    };
    std::mem::forget(local);

    // KeyDown monitors: cancel an in-progress bare-modifier dictation when the user
    // presses another key (using the modifier as a chord). Observe-only — the key
    // still reaches the focused app so chords like Option+Arrow keep working.
    let app_global_key = app.clone();
    let global_key = block2::RcBlock::new(move |_event: NonNull<NSEvent>| {
        dispatch_key_down(&app_global_key);
    });
    let _global_key_token =
        NSEvent::addGlobalMonitorForEventsMatchingMask_handler(NSEventMask::KeyDown, &global_key);
    std::mem::forget(global_key);

    let app_local_key = app.clone();
    let local_key = block2::RcBlock::new(move |event: NonNull<NSEvent>| -> *mut NSEvent {
        dispatch_key_down(&app_local_key);
        event.as_ptr()
    });
    let _local_key_token = unsafe {
        NSEvent::addLocalMonitorForEventsMatchingMask_handler(NSEventMask::KeyDown, &local_key)
    };
    std::mem::forget(local_key);

    tracing::info!("Modifier-key monitor installed");
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
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(AppState {
            settings: Mutex::new(app_settings),
            dictionary: Mutex::new(CustomDictionary::load()),
            snippets: Mutex::new(SnippetsStore::load()),
            commands: Mutex::new(VoiceCommandsStore::load()),
            history: Mutex::new(TranscriptionHistory::load()),
            audio_capture: Mutex::new(AudioCapture::new()),
            is_recording: Mutex::new(false),
            recording_stopped_at: Mutex::new(None),
            fallback_text: Mutex::new(None),
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
            get_fallback_text,
            dict_cloud_sign_up,
            dict_cloud_sign_in,
            dict_cloud_sign_out,
            dict_cloud_flags,
            models::list_llm_models,
            models::list_whisper_models,
            models::download_whisper_model,
            models::delete_whisper_model,
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

            // Install the native modifier/Fn key monitor (handles bare-modifier
            // triggers live, reading the current hotkey from settings).
            #[cfg(target_os = "macos")]
            install_modifier_monitor(app.handle());

            // Register the global hotkey from settings — unless it's a bare
            // modifier / Fn key, which the monitor above handles instead.
            {
                use tauri_plugin_global_shortcut::GlobalShortcutExt;
                let shortcut_str = {
                    let state = app.state::<AppState>();
                    let s = state.settings.lock().unwrap();
                    s.data.hotkey.clone()
                };
                let handler = |app: &AppHandle, _sc: &_, event: tauri_plugin_global_shortcut::ShortcutEvent| {
                    handle_hotkey_event(app, event.state);
                };
                if is_bare_modifier(&shortcut_str) {
                    tracing::info!("Modifier trigger active: {}", shortcut_str);
                } else if let Err(e) = app.global_shortcut().on_shortcut(shortcut_str.as_str(), handler) {
                    tracing::error!("Failed to register hotkey '{}': {}", shortcut_str, e);
                    // Fall back to the platform default so the app stays usable
                    let fallback = hotkey::default_hotkey();
                    let _ = app.global_shortcut().on_shortcut(fallback, handler);
                } else {
                    tracing::info!("Registered hotkey: {}", shortcut_str);
                }

                // Dedicated, always-on shortcut to open Preferences. The tray icon
                // can be swallowed by the menu-bar overflow / notch on a crowded
                // menu bar, so this guarantees a way into settings.
                let prefs_handler =
                    |app: &AppHandle, _sc: &_, event: tauri_plugin_global_shortcut::ShortcutEvent| {
                        if event.state == ShortcutState::Pressed {
                            open_preferences(app);
                        }
                    };
                match app
                    .global_shortcut()
                    .on_shortcut("CmdOrCtrl+Shift+Comma", prefs_handler)
                {
                    Ok(_) => tracing::info!("Registered Preferences shortcut: Cmd+Shift+,"),
                    Err(e) => tracing::error!("Failed to register Preferences shortcut: {}", e),
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
                    "preferences" => open_preferences(&app_handle),
                    "check_update" => updater::check_now(&app_handle),
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

                // Left-click shows the menu (reliable on macOS); "Preferences…" is
                // the first actionable item. Direct click-to-open isn't reliable for
                // a menu-attached tray icon, so we keep the menu as the entry point.
            }

            // Start over-the-air update checks (one shortly after launch, then every 6h).
            updater::start_background_checks(app.handle());

            // Show onboarding if first launch
            if show_onboarding {
                open_onboarding(app.handle());
            }

            tracing::info!(
                "Dict is running. Press {} to dictate.",
                app.state::<AppState>().settings.lock().unwrap().data.hotkey
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
