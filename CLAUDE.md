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

# Run the app
open Dict.app
```

There are no tests or linter configured yet. The project uses Swift Package Manager with no external dependencies — only macOS system frameworks (AppKit, Carbon, AVFoundation, Speech).

## Architecture

**AppDelegate** is the central orchestrator. It owns all components and wires them together:

```
HotkeyManager (Option+Space, Carbon API)
    → toggleRecording()
        → SpeechRecognizerManager (Apple on-device STT)
          OR WhisperSTT (records WAV → runs whisper-cli subprocess)
            → LLMProcessor (optional, OpenAI-compatible API cleanup)
                → TextInjector (clipboard + AppleScript Cmd+V paste)

RecordingOverlay (floating HUD with audio level bars, shown while recording)
Settings (singleton, persisted to ~/.config/dict/config.json)
```

**Key design decisions:**
- Carbon `RegisterEventHotKey` for the global hotkey — no Accessibility permission needed (unlike CGEvent taps)
- Whisper runs as a CLI subprocess (`whisper-cli`) rather than linked C++ library — simpler build, user installs via Homebrew
- Text injection uses AppleScript `System Events` keystroke as primary method, CGEvent as fallback — both require Accessibility permission
- `LSUIElement = true` in Info.plist — menu bar only, no dock icon
- Config lives at `~/.config/dict/config.json`, auto-created with defaults on first access

## Runtime Requirements

- macOS 14+
- Microphone + Speech Recognition permissions (prompted automatically)
- Accessibility permission (for text pasting — must be granted manually in System Settings)
- `brew install whisper-cpp` + a GGML model file if using Whisper engine
- An OpenAI-compatible API endpoint if LLM cleanup is enabled
