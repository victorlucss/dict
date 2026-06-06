use arboard::Clipboard;
use enigo::{Direction, Enigo, Key, Keyboard, Settings as EnigoSettings};
use std::thread;
use std::time::Duration;

/// Dispatch a closure synchronously to the main thread on macOS.
/// If already on the main thread, runs directly.
/// On non-macOS, runs directly (assumes caller is on an appropriate thread).
#[cfg(target_os = "macos")]
fn on_main_thread_sync<F: FnOnce() + Send>(f: F) {
    use std::ffi::c_void;

    extern "C" {
        fn pthread_main_np() -> i32;
        static _dispatch_main_q: c_void;
        fn dispatch_sync_f(
            queue: *const c_void,
            context: *mut c_void,
            work: extern "C" fn(*mut c_void),
        );
    }

    if unsafe { pthread_main_np() } == 1 {
        f();
    } else {
        struct Ctx<F: FnOnce()> {
            f: Option<F>,
        }

        extern "C" fn trampoline<F: FnOnce()>(ctx: *mut c_void) {
            let ctx = unsafe { &mut *(ctx as *mut Ctx<F>) };
            if let Some(f) = ctx.f.take() {
                f();
            }
        }

        let mut ctx = Ctx { f: Some(f) };
        unsafe {
            dispatch_sync_f(
                &_dispatch_main_q as *const c_void,
                &mut ctx as *mut Ctx<F> as *mut c_void,
                trampoline::<F>,
            );
        }
    }
}

#[cfg(not(target_os = "macos"))]
fn on_main_thread_sync<F: FnOnce() + Send>(f: F) {
    f();
}

/// Inject text into the focused application via clipboard paste.
/// Returns false if Accessibility permission is missing (caller should alert user).
pub fn inject_text(text: &str, flow_mode: bool) -> bool {
    // Check Accessibility permission before attempting paste
    #[cfg(target_os = "macos")]
    if !check_accessibility() {
        tracing::error!("Cannot paste: Accessibility permission not granted");
        return false;
    }

    // Small delay to ensure the target app has focus after overlay dismissal
    thread::sleep(Duration::from_millis(100));

    let mut clipboard = match Clipboard::new() {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("Failed to access clipboard: {}", e);
            return false;
        }
    };

    // Save previous clipboard contents
    let previous = clipboard.get_text().ok();

    // Set new text
    if let Err(e) = clipboard.set_text(text) {
        tracing::error!("Failed to set clipboard text: {}", e);
        return false;
    }

    tracing::info!("Pasting text (flow mode: {})", flow_mode);

    // Simulate paste shortcut — must run on main thread (HIToolbox requirement)
    on_main_thread_sync(simulate_paste);

    // Flow mode: press Enter after pasting to send the message
    if flow_mode {
        thread::sleep(Duration::from_millis(300));
        on_main_thread_sync(simulate_enter);
    }

    // Restore clipboard after a delay
    let restore_delay = if flow_mode { 1000 } else { 500 };
    let prev = previous.clone();
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(restore_delay));
        if let Ok(mut cb) = Clipboard::new() {
            cb.clear().ok();
            if let Some(text) = prev {
                cb.set_text(text).ok();
            }
        }
    });

    true
}

/// Simulate Cmd+V (macOS) or Ctrl+V (Windows/Linux)
fn simulate_paste() {
    let mut enigo = match Enigo::new(&EnigoSettings::default()) {
        Ok(e) => e,
        Err(e) => {
            tracing::error!("Failed to create enigo: {}", e);
            return;
        }
    };

    let modifier = if cfg!(target_os = "macos") {
        Key::Meta
    } else {
        Key::Control
    };

    enigo.key(modifier, Direction::Press).ok();
    enigo.key(Key::Unicode('v'), Direction::Click).ok();
    enigo.key(modifier, Direction::Release).ok();
}

/// Simulate Enter key press
fn simulate_enter() {
    let mut enigo = match Enigo::new(&EnigoSettings::default()) {
        Ok(e) => e,
        Err(e) => {
            tracing::error!("Failed to create enigo for Enter: {}", e);
            return;
        }
    };

    enigo.key(Key::Return, Direction::Click).ok();
    tracing::info!("Flow mode: Enter sent");
}

/// Simulate a keyboard shortcut from a combo string like "cmd+shift+3"
pub fn simulate_key_combo(combo: &str) {
    thread::sleep(Duration::from_millis(100));

    let combo_owned = combo.to_string();
    on_main_thread_sync(move || {
        simulate_key_combo_inner(&combo_owned);
    });
}

fn simulate_key_combo_inner(combo: &str) {
    let mut enigo = match Enigo::new(&EnigoSettings::default()) {
        Ok(e) => e,
        Err(e) => {
            tracing::error!("Failed to create enigo for key combo: {}", e);
            return;
        }
    };

    let lowered = combo.to_lowercase();
    let parts_owned: Vec<String> = lowered.split('+').map(|s| s.trim().to_string()).collect();

    if parts_owned.is_empty() {
        tracing::warn!("Invalid key combo: {}", combo);
        return;
    }

    // Press modifiers
    let modifiers: Vec<Key> = parts_owned[..parts_owned.len() - 1]
        .iter()
        .filter_map(|part| match part.as_str() {
            "cmd" | "command" => Some(if cfg!(target_os = "macos") {
                Key::Meta
            } else {
                Key::Control
            }),
            "shift" => Some(Key::Shift),
            "opt" | "option" | "alt" => Some(Key::Alt),
            "ctrl" | "control" => Some(Key::Control),
            other => {
                tracing::warn!("Unknown modifier: {}", other);
                None
            }
        })
        .collect();

    let key_name = &parts_owned[parts_owned.len() - 1];
    let key = match key_name.as_str() {
        "return" | "enter" => Key::Return,
        "tab" => Key::Tab,
        "space" => Key::Unicode(' '),
        "delete" | "backspace" => Key::Backspace,
        "escape" | "esc" => Key::Escape,
        "up" => Key::UpArrow,
        "down" => Key::DownArrow,
        "left" => Key::LeftArrow,
        "right" => Key::RightArrow,
        s if s.len() == 1 => Key::Unicode(s.chars().next().unwrap()),
        other => {
            tracing::warn!("Unknown key name: {}", other);
            return;
        }
    };

    // Press all modifiers
    for m in &modifiers {
        enigo.key(*m, Direction::Press).ok();
    }

    // Press and release the main key
    enigo.key(key, Direction::Click).ok();

    // Release modifiers in reverse
    for m in modifiers.iter().rev() {
        enigo.key(*m, Direction::Release).ok();
    }

    tracing::info!("Simulated key combo: {}", combo);
}

/// Check Accessibility permission status (macOS only)
#[cfg(target_os = "macos")]
pub fn check_accessibility() -> bool {
    // Use the macOS Accessibility API
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }
    let trusted = unsafe { AXIsProcessTrusted() };
    if trusted {
        tracing::info!("Accessibility: granted");
    } else {
        tracing::info!("Accessibility: not granted — text pasting may not work.");
    }
    trusted
}

#[cfg(not(target_os = "macos"))]
pub fn check_accessibility() -> bool {
    // On Linux/Windows, accessibility check is not needed
    true
}

/// Whether the currently focused UI element can actually receive typed text.
///
/// `inject_text` simulates Cmd+V, but a paste into a non-editable context just
/// bounces (the system "funk" beep) — and we can't see that from the keystroke.
/// So we ask the Accessibility API directly: is the system-wide focused element's
/// value settable, or is it a text-ish role? If nothing editable is focused (or
/// Accessibility is denied, which makes the query fail), this returns false and
/// the caller shows the copy-fallback popup instead of pasting into the void.
#[cfg(target_os = "macos")]
pub fn has_editable_focus() -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;
    use core_foundation_sys::base::{Boolean, CFRelease, CFTypeRef};
    use core_foundation_sys::string::CFStringRef;
    use std::ptr;

    const AX_OK: i32 = 0;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXUIElementCreateSystemWide() -> CFTypeRef;
        fn AXUIElementCopyAttributeValue(
            element: CFTypeRef,
            attribute: CFStringRef,
            value: *mut CFTypeRef,
        ) -> i32;
        fn AXUIElementIsAttributeSettable(
            element: CFTypeRef,
            attribute: CFStringRef,
            settable: *mut Boolean,
        ) -> i32;
    }

    unsafe {
        let system_wide = AXUIElementCreateSystemWide();
        if system_wide.is_null() {
            return false;
        }

        // The focused UI element across the whole system.
        let focused_attr = CFString::from_static_string("AXFocusedUIElement");
        let mut focused: CFTypeRef = ptr::null();
        let err = AXUIElementCopyAttributeValue(
            system_wide,
            focused_attr.as_concrete_TypeRef(),
            &mut focused,
        );
        CFRelease(system_wide as *const _);

        // No focused element (or no Accessibility trust) → treat as not editable.
        if err != AX_OK || focused.is_null() {
            return false;
        }

        // Primary signal: can we write to its AXValue? True for text fields/areas.
        let value_attr = CFString::from_static_string("AXValue");
        let mut settable: Boolean = 0;
        let settable_err = AXUIElementIsAttributeSettable(
            focused,
            value_attr.as_concrete_TypeRef(),
            &mut settable,
        );
        let value_settable = settable_err == AX_OK && settable != 0;

        // Backup signal: a text-ish role (covers fields that don't report settable).
        let role_is_text = {
            let role_attr = CFString::from_static_string("AXRole");
            let mut role_ref: CFTypeRef = ptr::null();
            let role_err = AXUIElementCopyAttributeValue(
                focused,
                role_attr.as_concrete_TypeRef(),
                &mut role_ref,
            );
            if role_err == AX_OK && !role_ref.is_null() {
                // CopyAttributeValue returns a +1 ref; wrap_under_create_rule frees it.
                let role = CFString::wrap_under_create_rule(role_ref as CFStringRef).to_string();
                matches!(
                    role.as_str(),
                    "AXTextField" | "AXTextArea" | "AXComboBox" | "AXSearchField"
                )
            } else {
                false
            }
        };

        CFRelease(focused as *const _);

        value_settable || role_is_text
    }
}

#[cfg(not(target_os = "macos"))]
pub fn has_editable_focus() -> bool {
    // On Linux/Windows we don't have this check yet; assume a paste target exists.
    true
}
