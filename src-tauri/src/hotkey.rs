/// Hotkey state for debouncing key-repeat events
pub struct HotkeyState {
    pub is_pressed: bool,
}

impl HotkeyState {
    pub fn new() -> Self {
        Self { is_pressed: false }
    }
}

/// Returns the default hotkey string for the current platform
pub fn default_hotkey() -> &'static str {
    if cfg!(target_os = "macos") {
        "Alt+Space"
    } else {
        "Ctrl+Alt+Space"
    }
}
