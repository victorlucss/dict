/// Returns the default hotkey string for the current platform
pub fn default_hotkey() -> &'static str {
    if cfg!(target_os = "macos") {
        "Alt+Space"
    } else {
        "Ctrl+Alt+Space"
    }
}
