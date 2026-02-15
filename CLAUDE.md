# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Dict?

Dict is a macOS menu-bar app that converts voice to text via a global hotkey (Option+Space). It supports two STT backends (Apple Speech, Whisper) with optional LLM post-processing, and pastes the result into whatever app has focus.

## Build Commands

```bash
# Debug build
swift build

# Release build + .app bundle
./scripts/build.sh

# Release build + .app bundle + DMG
./scripts/build.sh --dmg

# Release build + signed & notarized DMG
CODESIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE="dict-notary" ./scripts/build.sh --dmg

# Run the app
open Dict.app
```

There are no tests or linter configured yet. The project uses Swift Package Manager with no external dependencies — only macOS system frameworks (AppKit, Carbon, AVFoundation, Speech).

## Releasing

Versioning follows semver. The version lives in `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`).

To release a new version:
1. Bump the version in `Resources/Info.plist` (both `CFBundleShortVersionString` and `CFBundleVersion`)
2. Commit and push to `main`
3. The GitHub Actions pipeline (`.github/workflows/release.yml`) automatically:
   - Builds the DMG on a macOS 14 runner
   - Creates a GitHub Release tagged `vX.Y.Z` with the DMG attached
   - Skips if a tag for that version already exists

## Architecture

**AppDelegate** is the central orchestrator. It owns all components and wires them together:

```
HotkeyManager (Option+Space, Carbon API)
    → toggleRecording()
        → SpeechRecognizerManager (Apple on-device STT)
          OR WhisperSTT (records WAV → runs whisper-cli subprocess)
            → LLMProcessor (optional, OpenAI-compatible API cleanup, accuracy level)
                → TextInjector (clipboard + AppleScript Cmd+V paste)

RecordingOverlay (floating HUD with audio level bars, 15s limit with red warning border)
Settings (singleton, persisted to ~/.config/dict/config.json)
PreferencesWindow (sidebar + content pane layout, buffered UI — changes only apply on Save)
UpdateChecker (compares semver against remote, only prompts when remote > current)
```

**Key design decisions:**
- Carbon `RegisterEventHotKey` for the global hotkey — no Accessibility permission needed (unlike CGEvent taps)
- Whisper runs as a CLI subprocess (`whisper-cli`) rather than linked C++ library — simpler build, user installs via Homebrew
- Text injection uses AppleScript `System Events` keystroke as primary method, CGEvent as fallback — both require Accessibility permission
- `LSUIElement = true` in Info.plist — menu bar only, no dock icon
- Config lives at `~/.config/dict/config.json`, auto-created with defaults on first access
- Settings uses a custom `init(from:)` decoder so missing keys fall back to defaults — adding new settings won't break existing config files
- Preferences window uses sidebar + content pane layout (5 sections: General, Speech, LLM, Overlay, Files), buffers all changes until Save
- Push-to-talk mode guards against Carbon key-repeat events to avoid recreating the NSEvent monitor mid-hold
- Recording has a 15-second hard limit with a red border warning 3 seconds before cutoff
- LLM correction level (1–5 slider) controls how aggressively the LLM rewrites transcriptions — from minimal punctuation fixes to full rewriting
- Update checker does proper semver comparison; falls back to reading Info.plist from disk when Bundle.main is unavailable

## Supported Languages

Currently English and Brazilian Portuguese only. The language setting affects both Apple Speech (locale) and Whisper (`-l` flag). To add a new language:
1. Add an entry to `Settings.supportedLanguages`
2. Add a case in `SpeechRecognizerManager.localeIdentifier(for:)` to map the code to an Apple locale (e.g. `"pt"` → `"pt-BR"`)

## Runtime Requirements

- macOS 14+
- Microphone + Speech Recognition permissions (prompted automatically)
- Accessibility permission (for text pasting — must be granted manually in System Settings)
- `brew install whisper-cpp` + a GGML model file if using Whisper engine
- An OpenAI-compatible API endpoint if LLM cleanup is enabled
