# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Dict?

Dict is a cross-platform (macOS, Linux, Windows) menu-bar/tray app that converts voice to text via a global hotkey. It supports two STT backends (Apple Speech on macOS, Whisper on all platforms) with optional LLM post-processing, and pastes the result into whatever app has focus.

Built with **Rust + Tauri 2.0** for the backend and vanilla HTML/CSS/JS for the frontend.

## Build Commands

```bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Tauri CLI
cargo install tauri-cli --version "^2"

# Debug build (check only)
cd src-tauri && cargo check

# Run tests
cd src-tauri && cargo test

# Dev mode (hot-reload)
cd src-tauri && cargo tauri dev

# Release build (creates platform-specific bundle)
cd src-tauri && cargo tauri build
```

Tests: 4 unit tests in `src-tauri/src/settings.rs` (run via `cargo test`). No linter configured.

## Releasing

Versioning follows semver. The version lives in `src-tauri/tauri.conf.json` (the `version` field).

### Automated (GitHub Actions)

1. Bump the version in `src-tauri/tauri.conf.json`
2. Commit and push to `main`
3. The GitHub Actions pipeline (`.github/workflows/release.yml`) automatically:
   - Builds for macOS (aarch64 + x86_64), Linux (x86_64), and Windows (x86_64)
   - Creates a GitHub Release tagged `vX.Y.Z` with all platform installers
   - Skips if a tag for that version already exists

### Manual (local macOS build)

```bash
cd src-tauri && cargo tauri build
# Output: src-tauri/target/release/bundle/dmg/Dict_X.Y.Z_aarch64.dmg
```

## Architecture

The app is structured as a Tauri 2.0 application with a Rust backend and HTML/JS frontend.

### Backend (src-tauri/src/)

**lib.rs** is the central orchestrator. It manages state, registers Tauri commands, and wires everything together:

```
Global Hotkey (tauri-plugin-global-shortcut, Alt+Space / Ctrl+Alt+Space)
    → start_recording() / stop_recording()
        → Apple Speech (macOS: Swift FFI bridge via apple_speech.rs)
          OR Whisper (audio.rs capture → whisper.rs CLI subprocess)
            → LLM Processor (llm.rs: OpenAI/Anthropic/Ollama/LM Studio)
                → Text Injector (text_injector.rs: arboard clipboard + enigo paste)

System Tray (Tauri tray-icon: mode toggle, preferences, quit)
Recording Overlay (overlay window: animated dots, audio level)
Settings (settings.rs: serde JSON at ~/.config/dict/config.json)
Preferences Window (preferences/: sidebar + 5 sections, buffered save)
Update Checker (update_checker.rs: semver comparison against remote)
```

### Frontend (src/)

Vanilla HTML/CSS/JS with no build step:
- `overlay/` — Recording HUD with animated dots and audio level visualization
- `preferences/` — Settings UI with 5 sections (General, Speech, LLM, Overlay, Files)
- `onboarding/` — First-launch setup wizard (platform-aware steps)

### Key Modules

| Module | Purpose |
|--------|---------|
| `lib.rs` | App orchestration, state machine, Tauri commands, tray menu |
| `settings.rs` | SettingsData, persistence, custom dictionary, snippets, voice commands, history |
| `audio.rs` | cpal microphone capture, rubato resampling to 16kHz, hound WAV writing |
| `apple_speech.rs` | macOS-only Swift FFI bridge to SFSpeechRecognizer |
| `whisper.rs` | whisper-cli binary discovery and subprocess transcription |
| `llm.rs` | LLM post-processing (4 providers, correction levels 1-5) |
| `text_injector.rs` | Clipboard paste via arboard + enigo, key combo simulation |
| `hotkey.rs` | Hotkey defaults and debounce state |
| `frontmost_app.rs` | Platform-specific frontmost app detection |
| `update_checker.rs` | Remote version check with semver comparison |
| `logging.rs` | tracing-subscriber with file + stdout |

### Swift Bridge (macOS only)

`src-tauri/swift-bridge/DictSpeechBridge.swift` provides Apple Speech recognition via C FFI. It's compiled to a static library by `build.rs` and linked automatically. The bridge exposes:
- `dict_speech_start(language)` — Start streaming recognition
- `dict_speech_stop()` — Stop with 3s timeout for final result
- `dict_speech_cancel()` — Cancel immediately
- `dict_speech_set_callbacks(...)` — Register result/level/error callbacks

### Key Design Decisions

- Tauri 2.0 for cross-platform (macOS, Linux, Windows) with a single Rust codebase
- Apple Speech available only on macOS via Swift static library FFI bridge
- Whisper runs as a CLI subprocess (`whisper-cli`) on all platforms
- `tauri-plugin-global-shortcut` for hotkeys (Alt+Space on macOS, Ctrl+Alt+Space elsewhere)
- Text injection uses `arboard` (clipboard) + `enigo` (key simulation) — cross-platform
- `macOSPrivateApi: true` in tauri.conf.json + `LSUIElement` for menu-bar-only mode
- Config at `~/.config/dict/` (macOS/Linux) or `%APPDATA%/dict/` (Windows)
- Settings uses serde with `#[serde(default)]` so missing keys fall back to defaults
- Push-to-talk mode uses hotkey press/release events
- LLM correction level (1–5) controls rewriting aggressiveness

## Supported Languages

Currently English and Brazilian Portuguese. The `whisper_language` setting affects both Apple Speech (locale mapping in Swift bridge) and Whisper (`-l` flag).

## Runtime Requirements

- **macOS 14+** / **Linux** (with GTK3, WebKitGTK) / **Windows 10+**
- Microphone permission (prompted automatically)
- Accessibility permission on macOS (for text pasting — granted manually in System Settings)
- `brew install whisper-cpp` + a GGML model file if using Whisper engine
- An OpenAI-compatible API endpoint if LLM cleanup is enabled
