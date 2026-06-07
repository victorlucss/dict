<div align="center">

# Dict

**Talk instead of typing.** Dict is a cross-platform menu-bar / tray app that turns
your voice into clean text anywhere, with one hotkey.

[dict.studio](https://dict.studio) · [Download](https://github.com/victorlucss/dict/releases/latest) · [Changelog](https://dict.studio/changelog.html) · [Config reference](CONFIG.md)

</div>

---

Press your hotkey, talk, and clean text lands wherever your cursor is. Transcription
runs locally with Whisper; optional LLM cleanup fixes grammar and trims filler.
Runs on **macOS, Linux, and Windows**.

## Features

- **Local transcription** — Whisper (`whisper-cli` + a GGML model) runs on-device. Your audio never leaves your machine.
- **Optional cleanup** — fix grammar and drop fillers via Ollama, LM Studio, OpenAI, Anthropic, OpenRouter, or managed **Dict Cloud**. Five correction levels and a tone setting.
- **Works everywhere you type** — pastes into any app via the clipboard.
- **Voice snippets** — say a trigger, get a full expansion.
- **Voice commands** — map spoken phrases to keyboard shortcuts.
- **Configurable hotkey** — any accelerator, or a bare modifier (e.g. Control). Push-to-talk or toggle.
- **Privacy mode** — keep everything local and stop saving history.
- **Auto-updates** — signed over-the-air updates.

## Install

Download the installer for your platform from the
[latest release](https://github.com/victorlucss/dict/releases/latest), or grab it from
[dict.studio](https://dict.studio). Existing installs update themselves over the air.

You also need Whisper and a model:

```bash
brew install whisper-cpp   # or your platform's equivalent
```

Then download a GGML model (the in-app model manager under **Preferences → Speech**
can do this for you), and point `whisperModelPath` at it.

## Build from source

Requires Rust and the Tauri CLI.

```bash
# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install tauri-cli --version "^2"

cd src-tauri
cargo check          # quick type-check
cargo test           # unit tests
cargo tauri dev      # hot-reload dev build
cargo tauri build    # release bundle
```

## How it works

```
Hotkey → record (cpal) → Whisper (whisper-cli) → optional LLM cleanup → paste (clipboard + key sim)
```

Built with **Rust + Tauri 2.0**; the frontend is vanilla HTML/CSS/JS (no build step).
See [CLAUDE.md](CLAUDE.md) for the full architecture and [CONFIG.md](CONFIG.md) for
every config key.

## Runtime requirements

- macOS 14+ / Linux (GTK3, WebKitGTK) / Windows 10+
- Microphone permission (prompted automatically)
- Accessibility permission on macOS (for pasting into other apps)
- `whisper-cpp` + a GGML model
- An OpenAI-compatible endpoint or a Dict Cloud account if you enable LLM cleanup

## Languages

English and Brazilian Portuguese today (`whisperLanguage` maps to Whisper's `-l`
flag; `auto` lets Whisper detect).

## License

See the repository for license details.
