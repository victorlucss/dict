# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Dict?

Dict is a cross-platform (macOS, Linux, Windows) menu-bar/tray app that converts voice to text via a global hotkey. It uses Whisper (embedded whisper.cpp via whisper-rs, model kept warm in RAM) as its STT backend on all platforms, with optional LLM post-processing, and pastes the result into whatever app has focus.

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

Tests: unit tests in `src-tauri/src/settings.rs` and `src-tauri/src/lib.rs` (run via `cargo test`). CI runs `cargo check` + `cargo test` on every push/PR (`.github/workflows/ci.yml`). No linter configured.

## Releasing

Versioning follows semver. The version is duplicated in **both** `src-tauri/tauri.conf.json` (drives the release pipeline + OTA version) and `src-tauri/Cargo.toml` (drives the tray label + `X-Dict-Version` header) — bump both together or they diverge. `cargo build`/`cargo test` then updates `Cargo.lock` to match.

### Automated (GitHub Actions)

1. Bump the version in `src-tauri/tauri.conf.json` **and** `src-tauri/Cargo.toml` (keep them equal), then run `cargo check` so `Cargo.lock` updates
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
Global Hotkey (tauri-plugin-global-shortcut; bare modifiers via native NSEvent monitor on macOS)
    → start_recording() / stop_recording()
        → Whisper (audio.rs capture → 16kHz f32 samples → whisper.rs in-process whisper-rs, warm model)
            → LLM Processor (llm.rs: Dict Cloud / OpenAI / Anthropic / OpenRouter / Ollama / LM Studio)
                → Text Injector (text_injector.rs: arboard clipboard + enigo paste)

System Tray (Tauri tray-icon: mode toggle, preferences, check for updates, quit)
Recording Overlay (overlay window: animated dots, audio level)
Copy Fallback (popup with the text when paste isn't possible)
Settings (settings.rs: serde JSON at ~/.config/dict/config.json)
Preferences Window (preferences/: sidebar sections, auto-save on change)
OTA Updater (updater.rs: tauri-plugin-updater, signed latest.json from GitHub releases)
Dict Cloud (llm.rs → Convex backend: managed cleanup behind a per-user feature flag)
```

### Frontend (src/)

Vanilla HTML/CSS/JS with no build step:
- `overlay/` — Recording HUD with animated dots and audio level visualization
- `preferences/` — Settings UI (Account, General, Speech, LLM, Overlay, History, Dictionary, Snippets, Commands) with in-app editors for history/dictionary/snippets/voice-commands
- `onboarding/` — First-launch setup wizard (platform-aware; mental-model opener, model download, personalization, try-it)
- `fallback/` — Copy-fallback popup shown when Dict can't paste into the focused app

### Key Modules

| Module | Purpose |
|--------|---------|
| `lib.rs` | App orchestration, state machine, Tauri commands, tray menu |
| `settings.rs` | SettingsData, persistence, custom dictionary, snippets, voice commands, history |
| `audio.rs` | cpal microphone capture, rubato resampling to 16kHz, returns f32 samples for whisper-rs |
| `whisper.rs` | Embedded whisper.cpp (whisper-rs): loads the GGML model once into a warm WhisperContext, in-process transcription (the sole STT engine) |
| `llm.rs` | LLM post-processing (6 providers: Dict Cloud, OpenAI, Anthropic, OpenRouter, Ollama, LM Studio; correction levels 1-5; tone) |
| `models.rs` | Whisper model catalog + downloader (in-app model manager) |
| `text_injector.rs` | Clipboard paste via arboard + enigo, key combo simulation |
| `hotkey.rs` | Hotkey defaults and debounce state |
| `frontmost_app.rs` | Platform-specific frontmost app detection |
| `updater.rs` | OTA self-update via tauri-plugin-updater (launch + every 6h + manual tray check) |
| `update_checker.rs` | Legacy remote version check (superseded by `updater.rs`) |
| `logging.rs` | tracing-subscriber with file + stdout |

### Key Design Decisions

- Tauri 2.0 for cross-platform (macOS, Linux, Windows) with a single Rust codebase — no platform-specific STT, so the build has no Swift/native bridge to compile
- Whisper (embedded whisper.cpp via whisper-rs; the GGML model is loaded once and kept warm in RAM, Metal-accelerated on Apple Silicon) is the sole STT engine on all platforms
- Recording runs while the hotkey is held (push-to-talk) or until toggled off, with a 10-minute safety cap (`audio::MAX_RECORDING_SECS`): the capture callback stops buffering at the cap and a per-recording watchdog thread auto-stops the session. On macOS the watchdog also stops bare-modifier PTT recordings whose Release event was lost (secure-input fields, screen lock, left/right modifier aliasing) by polling `CGEventSourceKeyState`. The tray shows 🔴 while recording
- `privacy_mode` skips cloud LLM providers (Dict Cloud / OpenAI / Anthropic / OpenRouter) and suppresses history persistence; local providers (Ollama, LM Studio) still run
- Dict Cloud is managed cleanup via a Convex backend, gated per-user by a `cloud_cleanup` feature flag; the client only shows it as a provider when signed in and the flag is on
- OTA self-updates via `tauri-plugin-updater` against a signed `latest.json` on GitHub releases (requires a public repo); the release CI rebuilds `latest.json` once across all platforms
- `tauri-plugin-global-shortcut` for accelerator hotkeys (default Alt+Space on macOS, Ctrl+Alt+Space elsewhere); the hotkey is configurable, and bare modifiers (e.g. Control) are handled by a native NSEvent monitor on macOS. Pressing another key during a bare-modifier recording cancels it (chord like Option+Arrow)
- Text injection uses `arboard` (clipboard) + `enigo` (key simulation) — cross-platform
- `macOSPrivateApi: true` in tauri.conf.json + `LSUIElement` for menu-bar-only mode
- Config at `~/.config/dict/` (macOS/Linux) or `%APPDATA%/dict/` (Windows)
- Settings uses serde with `#[serde(default)]` so missing keys fall back to defaults
- Push-to-talk mode uses hotkey press/release events
- LLM correction level (1–5) controls rewriting aggressiveness

## Supported Languages

Currently English and Brazilian Portuguese. The `whisper_language` setting maps to Whisper's `-l` flag.

## Runtime Requirements

- **macOS 14+** / **Linux** (with GTK3, WebKitGTK) / **Windows 10+**
- Microphone permission (prompted automatically)
- Accessibility permission on macOS (for text pasting — granted manually in System Settings)
- A GGML model file (the in-app model manager downloads one) — required. whisper.cpp is embedded, so there is no separate engine to install.
- An OpenAI-compatible API endpoint if LLM cleanup is enabled
